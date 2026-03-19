#!/usr/bin/Rscript

# This script is adapted from https://github.com/OHDSI/Broadsea-Achilles. We use our own entrypoint because the original
# version does not provide a way to override the JSON export functionality.

# Load Achilles DatabaseConnector, and httr.
library(Achilles)
library(httr)
library(DatabaseConnector)

env_var_names <- c(
  "ACHILLES_SOURCE",
  "ACHILLES_DB_URI",
  "ACHILLES_DB_USERNAME",
  "ACHILLES_DB_PASSWORD",
  "ACHILLES_CDM_SCHEMA",
  "ACHILLES_VOCAB_SCHEMA",
  "ACHILLES_RESULTS_SCHEMA",
  "ATLAS_WEB_API_SCHEMA",
  "ACHILLES_OUTPUT_BASE",
  "ACHILLES_CDM_VERSION",
  "ACHILLES_NUM_THREADS"
)
env_vars <- as.list(Sys.getenv(env_var_names, unset = NA))
names(env_vars) <- env_var_names

# Set defaults if missing
default_vars <- list(
  ACHILLES_SOURCE = "unknown",
  ACHILLES_DB_URI = "postgresql://localhost:5432/postgres",
  ACHILLES_DB_USERNAME = "",
  ACHILLES_DB_PASSWORD = "",
  ACHILLES_CDM_SCHEMA = "public",
  ACHILLES_VOCAB_SCHEMA = "public",
  ACHILLES_RESULTS_SCHEMA = "webapi",
  ATLAS_WEB_API_SCHEMA = "webapi",
  ACHILLES_OUTPUT_BASE = "/opt/achilles/workspace",
  ACHILLES_CDM_VERSION = "5.4",
  ACHILLES_NUM_THREADS = "1"
)

for (name in names(default_vars)) {
  if (is.na(env_vars[[name]]) || env_vars[[name]] == "") {
    env_vars[[name]] <- default_vars[[name]]
  }
}

env_vars$ACHILLES_NUM_THREADS <- as.numeric(env_vars$ACHILLES_NUM_THREADS)

current_datetime <- strftime(Sys.time(), format = "%Y-%m-%dT%H.%M.%S")
output_path <- file.path(env_vars$ACHILLES_OUTPUT_BASE, env_vars$ACHILLES_SOURCE, current_datetime)
dir.create(output_path, recursive = TRUE, showWarnings = FALSE, mode = "0755")

# Parse DB URI into pieces.
db_conf <- parse_url(env_vars$ACHILLES_DB_URI)
db_name <- sub("^/", "", db_conf$path)             # remove leading slash
server <- paste0(db_conf$hostname, "/", db_name)   # host/database for PostgreSQL

# Use env variables if set, else fall back to URI
db_username <- ifelse(env_vars$ACHILLES_DB_USERNAME == "" | is.na(env_vars$ACHILLES_DB_USERNAME),
                      db_conf$username,
                      env_vars$ACHILLES_DB_USERNAME)
db_password <- ifelse(env_vars$ACHILLES_DB_PASSWORD == "" | is.na(env_vars$ACHILLES_DB_PASSWORD),
                      db_conf$password,
                      env_vars$ACHILLES_DB_PASSWORD)

# Create connection details using DatabaseConnector utility.
connectionDetails <- createConnectionDetails(
  dbms = db_conf$scheme,
  user = db_username,
  password = db_password,
  server = server,
  port = db_conf$port
)

# --- CREATE SCHEMAS IF NOT EXIST ---
conn <- connect(connectionDetails)
createSchemaIfNotExists <- function(conn, schemaName) {
  if (!is.na(schemaName) && schemaName != "") {
    sql <- paste0("CREATE SCHEMA IF NOT EXISTS ", schemaName, ";")
    executeSql(conn, sql, progressBar = FALSE, reportOverallTime = FALSE)
  }
}

createSchemaIfNotExists(conn, env_vars$ACHILLES_RESULTS_SCHEMA)
createSchemaIfNotExists(conn, env_vars$ATLAS_WEB_API_SCHEMA)

disconnect(conn)

args <- commandArgs(trailingOnly = TRUE)
createIndices <- !(db_conf$scheme %in% c("redshift", "netezza"))

if (length(args) == 0 || args[1] != "heel") {
  # Run Achilles report and generate data in the results schema.
  achillesResults <- achilles(
    connectionDetails,
    cdmDatabaseSchema = env_vars$ACHILLES_CDM_SCHEMA,
    resultsDatabaseSchema = env_vars$ACHILLES_RESULTS_SCHEMA,
    vocabDatabaseSchema = env_vars$ACHILLES_VOCAB_SCHEMA,
    sourceName = env_vars$ACHILLES_SOURCE,
    cdmVersion = env_vars$ACHILLES_CDM_VERSION,
    createIndices = createIndices,
    numThreads = env_vars$ACHILLES_NUM_THREADS
  )

  # 2. NEW: Build the concept_hierarchy and Atlas cache tables
    message("Building Atlas cache and concept_hierarchy tables...")
    optimizeAtlasCache(
      connectionDetails = connectionDetails,
      resultsDatabaseSchema = env_vars$ACHILLES_RESULTS_SCHEMA,
      vocabDatabaseSchema = env_vars$ACHILLES_VOCAB_SCHEMA
    )

} else {
  # Run Achilles Heel only
  achillesHeel(
    connectionDetails,
    cdmDatabaseSchema = env_vars$ACHILLES_CDM_SCHEMA,
    resultsDatabaseSchema = env_vars$ACHILLES_RESULTS_SCHEMA,
    vocabDatabaseSchema = env_vars$ACHILLES_VOCAB_SCHEMA,
    cdmVersion = env_vars$ACHILLES_CDM_VERSION,
    numThreads = env_vars$ACHILLES_NUM_THREADS
  )
}
