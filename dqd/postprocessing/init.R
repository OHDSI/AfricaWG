#!/usr/bin/Rscript

# Get passed environment variables.
envVarNames <- list(
    "CDM_CONNECTIONDETAILS_DBMS",
    "CDM_CONNECTIONDETAILS_USER",
    "CDM_CONNECTIONDETAILS_SERVER",
    "CDM_CONNECTIONDETAILS_PORT",
    "CDM_CONNECTIONDETAILS_EXTRA_SETTINGS",
    "CDM_DATABASE_SCHEMA",
    "RESULTS_DATABASE_SCHEMA",
    "VOCAB_DATABASE_SCHEMA",
    "SCRATCH_DATABASE_SCHEMA",
    "TEMP_EMULATION_SCHEMA",
    "CDM_SOURCE_NAME",
    "CDM_VERSION"
)

env_vars <- Sys.getenv(envVarNames, unset = NA)

# Replace unset environment variables with defaults aligned to your docker-compose setup.
default_vars <- list(
    "postgresql",                    # CDM_CONNECTIONDETAILS_DBMS
    "postgres",                      # CDM_CONNECTIONDETAILS_USER
    "omop-db/postgres",              # CDM_CONNECTIONDETAILS_SERVER
    "5432",                          # CDM_CONNECTIONDETAILS_PORT
    "",                              # CDM_CONNECTIONDETAILS_EXTRA_SETTINGS
    "public",                        # CDM_DATABASE_SCHEMA
    "public",                        # RESULTS_DATABASE_SCHEMA
    "public",                        # VOCAB_DATABASE_SCHEMA
    "public",                        # SCRATCH_DATABASE_SCHEMA
    "",                              # TEMP_EMULATION_SCHEMA
    "OpenMRS",                       # CDM_SOURCE_NAME
    "5.4"                            # CDM_VERSION
)
env_vars[is.na(env_vars)] <- default_vars[is.na(env_vars)]

# Map back to expected variables or access via list
cdmConfig <- as.list(env_vars)
names(cdmConfig) <- envVarNames

# Download JDBC drivers using the configured DBMS value
DatabaseConnector::downloadJdbcDrivers(
    dbms = cdmConfig$CDM_CONNECTIONDETAILS_DBMS, 
    pathToDriver = '/jdbc'
)

# Create connection details using environment variables or fallbacks
connectionDetails <- DatabaseConnector::createConnectionDetails(
    dbms = cdmConfig$CDM_CONNECTIONDETAILS_DBMS,
    user = cdmConfig$CDM_CONNECTIONDETAILS_USER,
    password = Sys.getenv("CDM_CONNECTIONDETAILS_PASSWORD", unset = "postgres_pass"),
    server = cdmConfig$CDM_CONNECTIONDETAILS_SERVER,
    port = cdmConfig$CDM_CONNECTIONDETAILS_PORT,
    extraSettings = cdmConfig$CDM_CONNECTIONDETAILS_EXTRA_SETTINGS,
    pathToDriver = "/jdbc"
)