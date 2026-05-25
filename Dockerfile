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
ENV PGOPTIONS="--search_path=omop"


# copy the below SQL files into the container image - postgresql database will automatically run them in this sequence when it starts up
COPY ./vocabularies/*.csv ./

COPY ./vocabularies/*.zip ./

RUN for f in *.zip; do unzip "$f" && rm "$f"; done || true

# 010 - create empty atlas omop & atlas cdm_results schemas
COPY 010_create_cdm_schemas.sql /docker-entrypoint-initdb.d/010_create_cdm_schemas.sql

# 015 - create atlas omop schema tables - use vendored SQL
COPY ./vendor/cdm/omop_cdm_postgres_ddl.sql /docker-entrypoint-initdb.d/020_omop_cdm_postgresql_ddl.sql

# 020 - create empty achilles tables in the atlas cdm_results schema
COPY 020_achilles_postgresql_ddl.sql /docker-entrypoint-initdb.d/020_achilles_postgresql_ddl.sql

# 030 - load vocabularies cdm csv data into the atlas omop schema tables & achilles data into atlas cdm_results schema achilles tables
COPY 030_load_cdm_vocabularies.sql /docker-entrypoint-initdb.d/

# 040 - create atlas omop schema table primary keys
COPY 040_omop_cdm_postgresql_primary_keys.sql /docker-entrypoint-initdb.d/040_omop_cdm_postgresql_primary_keys.sql

# 050 - create atlas omop schema table indexes
COPY ./050_omop_cdm_postgresql_indexes.sql /docker-entrypoint-initdb.d/050_omop_cdm_postgresql_indexes.sql

# 060 - create atlas omop schema table database constraints - referential integrity
COPY ./060_omop_cdm_postgresql_constraints.sql /docker-entrypoint-initdb.d/060_omop_cdm_postgresql_constraints.sql

# 070 - populate cdm_source with the data source info
COPY 070_populate_cdm_source.sql /docker-entrypoint-initdb.d/070_populate_cdm_source.sql

# 080 - create an empty webapi schema
COPY 080_create_webapi_schema_postgresql.sql /docker-entrypoint-initdb.d/080_create_webapi_schema_postgresql.sql

# 085 - create the atlas cdm_results schema tables - use vendored SQL
COPY ./vendor/webapi/results_postgresql.ddl /docker-entrypoint-initdb.d/085_results_schema_ddl_postgresql.sql

# 089 - apply the webapi schema tables flyway database migration postgresql SQL files up to baseline version V2.2.5.20180212152023 - use vendored SQL
COPY ./vendor/webapi/webapi_baseline_V2.2.5.20180212152023_postgresql.sql /docker-entrypoint-initdb.d/089_webapi_flyway_migrations_postgresql.sql

# 090 - create and populate webapi_security schema - Atlas ohdsi and admin users
COPY 090_create_and_populate_webapi_security_schema.sql /docker-entrypoint-initdb.d/090_create_and_populate_webapi_security_schema.sql

# 0100 - create and populate webapi roles and users - Atlas ohdsi and admin user roles
COPY 100_create_sec_roles_and_users.sql /docker-entrypoint-initdb.d/100_create_sec_roles_and_users.sql

# 110 - populate the source and source daimon tables in the Atlas webapi schema - enables Atlas connection to this Atlas postgresql database with a demo CDM
COPY 110_populate_source_source_daimon.sql /docker-entrypoint-initdb.d/110_populate_source_source_daimon.sql

# 120 - create the flyway data migration history table
COPY 120_create_flyway_schema_history_table.sql /docker-entrypoint-initdb.d/120_create_flyway_schema_history_table.sql

# 130 - populate the flyway database migration history table with the correct entries up to baseline version V2.2.5.20180212152023
# Atlas will automatically migrate the webapi schema tables from this baseline version to the latest version when it starts up and connects to this Atlas postgresql database with a demo CDM
COPY 130_populate_flyway_schema_history_table.sql /docker-entrypoint-initdb.d/130_populate_flyway_schema_history_table.sql


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
