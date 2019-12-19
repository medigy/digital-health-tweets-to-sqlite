SHELL := /bin/bash
MAKEFLAGS := silent

TWITTER_AUTH_FILE := ./twitter-credentials.json

TTS_CONTENT_DB_FILE := content.sqlite
TTS_CONTENT_DB_COMPRESSED_FILE := content.sqlite.gz
TTS_CRITERIA_DB_FILE := criteria.sqlite

DOC_SCHEMA_HOME := doc/schema
DOC_SCHEMA_CONTENT_HOME := $(DOC_SCHEMA_HOME)/$(TTS_CONTENT_DB_FILE)
DOC_SCHEMA_CRITERIA_HOME := $(DOC_SCHEMA_HOME)/$(TTS_CRITERIA_DB_FILE)

BACKUPS_HOME := ./backups

$(TWITTER_AUTH_FILE):
	$(error $(NEWLINE)Twitter Credentials file $(YELLOW)$(TWITTER_AUTH_FILE)$(RESET) is missing.$(NEWLINE)Run $(GREEN)'make auth'$(RESET).$(NEWLINE)Use $(YELLOW)https://developer.twitter.com/en/apps$(RESET) to find your Twitter app credentials)

# We keep the latest SQLite database in a compressed .gz file for storage in Git
$(TTS_CONTENT_DB_FILE): $(TTS_CONTENT_DB_COMPRESSED_FILE)
	echo "Unzipping $(TTS_CONTENT_DB_FILE) from $(TTS_CONTENT_DB_COMPRESSED_FILE)"
	gunzip $(TTS_CONTENT_DB_COMPRESSED_FILE)

$(TTS_CRITERIA_DB_FILE): criteria/influencers.csv criteria/search-queries.csv
	echo "Recreating $(TTS_CRITERIA_DB_FILE) using criteria/*"
	rm -f $(TTS_CRITERIA_DB_FILE)
	sqlitebiter -o $(TTS_CRITERIA_DB_FILE) file criteria/influencers.csv criteria/search-queries.csv

$(DOC_SCHEMA_CONTENT_HOME): $(TTS_CONTENT_DB_FILE)
	java -jar /usr/local/bin/schemaspy.jar -t sqlite-xerial -db $(TTS_CONTENT_DB_FILE) -cat % -schemas "Content" -sso -dp /usr/local/bin/sqlite-jdbc.jar -o $(DOC_SCHEMA_CONTENT_HOME)

$(DOC_SCHEMA_CRITERIA_HOME): $(TTS_CRITERIA_DB_FILE)
	java -jar /usr/local/bin/schemaspy.jar -t sqlite-xerial -db $(TTS_CRITERIA_DB_FILE) -cat % -schemas "Criteria" -sso -dp /usr/local/bin/sqlite-jdbc.jar -o $(DOC_SCHEMA_CRITERIA_HOME)

.ONESHELL:
## Backup the content and criteria databases
backup:
	export BACKUP_PATH=$(BACKUPS_HOME)/`date +%Y-%m-%d_%H-%M-%S`
	mkdir -p $$BACKUP_PATH
	echo "Backing up $(TTS_CONTENT_DB_COMPRESSED_FILE) and $(TTS_CRITERIA_DB_FILE) to $$BACKUP_PATH"
	cp $(TTS_CONTENT_DB_COMPRESSED_FILE) $(TTS_CRITERIA_DB_FILE) $$BACKUP_PATH

## Create the Twitter criteria database so it can be used by other targets
criteria: $(TTS_CRITERIA_DB_FILE)

## Prepare the Twitter Credentials file, required by the other targets
auth:
	twitter-to-sqlite auth --auth $(TWITTER_AUTH_FILE)

.ONESHELL:
## Using queries in the criteria database, run searches and populate Tweets in the content database
search: $(TWITTER_AUTH_FILE) backup $(TTS_CONTENT_DB_FILE) $(TTS_CRITERIA_DB_FILE)
	sqlite3 $(TTS_CRITERIA_DB_FILE) "SELECT query FROM search_queries" | while read query
	do
		echo "Searching Twitter for '$$query' using twitter-to-sqlite, storing in $(TTS_CONTENT_DB_FILE)"
		echo "Simulate searching... | - | \ / "
		twitter-to-sqlite search $(TTS_CONTENT_DB_FILE) "$$query" --auth $(TWITTER_AUTH_FILE) --since
		sleep 1s
	done
	echo "Compressing $(TTS_CONTENT_DB_FILE): $(TTS_CONTENT_DB_COMPRESSED_FILE)"
	gzip --force --keep $(TTS_CONTENT_DB_FILE)

## Serve sqlite files through datasette
datasette: 
	datasette serve --host 0.0.0.0 --port 8001 --immutable $(TTS_CRITERIA_DB_FILE) --immutable $(TTS_CONTENT_DB_FILE)

## Reduce the size of SQLite databases by running OPTIMIZE for full text search tables, then VACUUM
compact: backup $(TTS_CONTENT_DB_FILE)
	sqlite-utils optimize $(TTS_CONTENT_DB_FILE)
	echo "Compressing $(TTS_CONTENT_DB_FILE): $(TTS_CONTENT_DB_COMPRESSED_FILE)"
	gzip --force --keep $(TTS_CONTENT_DB_FILE)

## Create schema documentation for all the databases in this package
schema-doc: criteria $(DOC_SCHEMA_CONTENT_HOME) $(DOC_SCHEMA_CRITERIA_HOME)

## Remove all derived artifacts
clean:
	rm -f $(TTS_CRITERIA_DB_FILE)
	rm -rf $(DOC_SCHEMA_HOME)

TARGET_MAX_CHAR_NUM=15
# All targets should have a ## Help text above the target and they'll be automatically collected
# Show help, using auto generator from https://gist.github.com/prwhite/8168133
help:
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "  ${YELLOW}%-$(TARGET_MAX_CHAR_NUM)s${RESET} ${WHITE}%s${RESET}\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)

GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

comma := ,
define logInfo
	if [ "$(CCF_LOG_LEVEL)" = 'INFO' ]; then
		echo "$1"
	fi
endef

define NEWLINE


endef
