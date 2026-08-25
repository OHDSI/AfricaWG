ARG PASSWORD_METHOD=default

#
# Vendored build: use pre-generated SQL artifacts committed under vendor
# If you need to regenerate those artifacts, run: make regen-webapi-sql
#

FROM postgres:16.4-alpine AS data-loader-image

WORKDIR /docker-entrypoint-initdb.d

EXPOSE 5432

# configure postgres database defaults
ENV PGDATA=/data
ENV PGOPTIONS="--search_path=public"


# copy the below SQL files into the container image - postgresql database will automatically run them in this sequence when it starts up
COPY ./vocabularies/*.csv ./

COPY ./vocabularies/*.zip ./

RUN for f in *.zip; do unzip "$f" && rm "$f"; done || true


# 010 - create empty atlas cdm & atlas schemas
COPY 010_create_cdm_schemas.sql /docker-entrypoint-initdb.d/010_create_cdm_schemas.sql

# 020 - create atlas cdm schema tables - use vendored SQL
COPY omop_cdm_postgres_ddl.sql /docker-entrypoint-initdb.d/020_omop_cdm_postgresql_ddl.sql

# 035 - create concept_recommended table in the atlas cdm schema for Atlas Phoebe recommendations functionality
COPY 035_concept_recommended.ddl.sql /docker-entrypoint-initdb.d/035_concept_recommended.ddl.sql

# 040 - load vocabularies cdm csv data into the atlas omop schema tables & achilles data into atlas cdm_results schema achilles tables
COPY 040_load_cdm_vocabularies.sql /docker-entrypoint-initdb.d/

# 045 - create atlas cdm schema table primary keys
COPY 045_omop_cdm_postgresql_primary_keys.sql /docker-entrypoint-initdb.d/045_omop_cdm_postgresql_primary_keys.sql

# 050 - create atlas cdm schema table indexes
COPY 050_omop_cdm_postgresql_indexes.sql /docker-entrypoint-initdb.d/050_omop_cdm_postgresql_indexes.sql

# 060 - create atlas cdm schema table database constraints - referential integrity
COPY 060_omop_cdm_postgresql_constraints.sql /docker-entrypoint-initdb.d/060_omop_cdm_postgresql_constraints.sql


# 070 - populate cdm_source table
COPY 070_populate_cdm_source.sql /docker-entrypoint-initdb.d/070_populate_cdm_source.sql

# 065 - create the atlas demo_cdm_results schema tables - use vendored SQL
COPY results_postgresql.ddl /docker-entrypoint-initdb.d/065_results_schema_ddl_postgresql.sql

# 075 - apply the webapi schema tables flyway database migration postgresql SQL files up to baseline version V2.2.5.20180212152023 - use vendored SQL
#COPY webapi_baseline_V2.2.5.20180212152023_postgresql.sql /docker-entrypoint-initdb.d/075_webapi_flyway_migrations_postgresql.sql

# 080 - create and populate webapi_security schema - Atlas ohdsi and admin users
COPY 080_create_and_populate_webapi_security_schema.sql /docker-entrypoint-initdb.d/080_create_and_populate_webapi_security_schema.sql



RUN ["sed", "-i", "s/exec \"$@\"/echo \"skipping...\"/", "/usr/local/bin/docker-entrypoint.sh"]

# Pseudo branching logic - we run 2 stages, 1 for default password auth, the other for secrets auth
FROM data-loader-image AS use-password-default
ENV POSTGRES_PASSWORD=postgres_pass
RUN ["/usr/local/bin/docker-entrypoint.sh", "postgres"]

FROM data-loader-image AS use-password-secret
ENV POSTGRES_PASSWORD_FILE="/run/secrets/OHDSI_ETL_POSTGRES_DB_PASSWORD"
RUN --mount=type=secret,id=OHDSI_ETL_POSTGRES_DB_PASSWORD \
    ["/usr/local/bin/docker-entrypoint.sh", "postgres"]

# then pick the stage based on the PASSWORD_METHOD
FROM use-password-${PASSWORD_METHOD} AS data-loader-image-final


# run the postgres entrypoint script to run the SQL scripts and load the data but do not start the postgres daemon process
FROM postgres:16.4-alpine
COPY --from=data-loader-image-final /data $PGDATA
