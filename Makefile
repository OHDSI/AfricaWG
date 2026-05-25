# Makefile: regenerate and clean vendored WebAPI SQL artifacts

.PHONY: help regen-webapi-sql clean clean-sqlrender

# Defaults (override via: make SQLRENDER_VERSION=1.16.1 WEBAPI_VERSION=v2.15.0 CDM_VERSION=v5.4.2)
# Export to child processes so scripts pick it up (keeps versions in sync)
SQLRENDER_VERSION?=1.16.1
WEBAPI_VERSION?=v2.15.0
CDM_VERSION?=v5.4.2
export SQLRENDER_VERSION
export WEBAPI_VERSION
export CDM_VERSION

help:
	@echo "Targets:"
	@echo "  regen-webapi-sql        Regenerate vendor/webapi SQL artifacts (requires git, java, and mvn/curl/wget)"
	@echo "  clean                   Remove ALL vendored artifacts (keeps local Maven SqlRender cache)"
	@echo "  clean-sqlrender         Purge SqlRender from local Maven repo and remove temp SqlRender.jar"

# Regenerate vendored WebAPI-derived SQL artifacts
regen-webapi-sql:
	bash scripts/regenerate_webapi_sql.sh

# Remove vendored SQL artifacts
clean:
	rm -rf vendor/webapi/*.sql vendor/webapi/*.ddl vendor/cdm/*.sql .tmp_webapi_gen

# Remove SqlRender artifacts from local Maven cache
clean-sqlrender:
	@REPO_DIR=$$(mvn -q -DforceStdout help:evaluate -Dexpression=settings.localRepository 2>/dev/null || echo $$HOME/.m2/repository); \
	set -e; \
	echo "Purging SqlRender $$SQLRENDER_VERSION from $$REPO_DIR"; \
	rm -rf "$$REPO_DIR/org/ohdsi/sql/SqlRender/$$SQLRENDER_VERSION" || true; \
	rm -rf "$$REPO_DIR/org/ohdsi/SqlRender/$$SQLRENDER_VERSION" || true

