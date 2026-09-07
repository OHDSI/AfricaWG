library(plumber)
library(DataQualityDashboard)
library(DatabaseConnector)
library(jsonlite)

# ==============================================================================
# Base Path & Helper Configuration
# ==============================================================================
BASE_PATH <- Sys.getenv("SHINY_SERVER_BASE_PATH", "/dqd")

get_base_url <- function() {
  if (nchar(BASE_PATH) > 0) {
    base <- if (substr(BASE_PATH, 1, 1) != "/") paste0("/", BASE_PATH) else BASE_PATH
    base <- if (substr(base, nchar(base), nchar(base)) == "/") {
      substr(base, 1, nchar(base) - 1)
    } else {
      base
    }
    return(base)
  }
  return("")
}

# Clean leading/trailing single/double quotes from string values
clean_env_string <- function(val, default_val = "") {
  if (is.null(val) || length(val) == 0 || nchar(trimws(val)) == 0) return(default_val)
  cleaned <- gsub("^['\"]|['\"]$", "", trimws(val))
  if (nchar(cleaned) == 0) return(default_val)
  return(cleaned)
}

# Clean double or redundant slashes from file paths
sanitize_path_name <- function(path_str) {
  gsub("/+", "/", path_str)
}

# ==============================================================================
# Environment Variables & Configuration
# ==============================================================================
CDM_SCHEMA      <- clean_env_string(Sys.getenv("CDM_SCHEMA"), "public")
VOCAB_SCHEMA    <- clean_env_string(Sys.getenv("VOCAB_SCHEMA"), "public")
RESULTS_SCHEMA  <- clean_env_string(Sys.getenv("RESULTS_SCHEMA"), "cdm_results")
CDM_SOURCE_NAME <- clean_env_string(Sys.getenv("CDM_SOURCE_NAME"), "OMRS")
NUM_THREADS     <- as.integer(clean_env_string(Sys.getenv("NUM_THREADS"), "1"))

# ==============================================================================
# Connection Details Helper
# ==============================================================================
get_connection_details <- function() {
  db_host   <- clean_env_string(Sys.getenv("TARGET_DB_HOST", Sys.getenv("DB_HOST")), "omop-db")
  db_port   <- clean_env_string(Sys.getenv("TARGET_DB_PORT", Sys.getenv("DB_PORT")), "5432")
  db_name   <- clean_env_string(Sys.getenv("TARGET_DB_NAME", Sys.getenv("DB_NAME")), "postgres")
  db_user   <- clean_env_string(Sys.getenv("TARGET_DB_USER", Sys.getenv("DB_USER")), "postgres")
  db_pass   <- clean_env_string(Sys.getenv("TARGET_DB_PASSWORD", Sys.getenv("DB_PASSWORD")), "postgres_pass")
  db_engine <- clean_env_string(Sys.getenv("DB_ENGINE"), "postgresql")

  DatabaseConnector::createConnectionDetails(
    dbms = db_engine,
    server = paste0(db_host, "/", db_name),
    port = as.integer(db_port),
    user = db_user,
    password = db_pass,
    pathToDriver = "/app/jdbc"
  )
}

# ==============================================================================
# Directory Helpers
# ==============================================================================
get_base_results_dir <- function() {
  return("/results")
}

get_source_dir <- function() {
  return(file.path(get_base_results_dir(), clean_env_string(CDM_SOURCE_NAME, "OMRS")))
}

# Safe initialization of output directories
dir.create(get_base_results_dir(), showWarnings = FALSE, recursive = TRUE)
dir.create(get_source_dir(), showWarnings = FALSE, recursive = TRUE)

# Cleanup helper for rogue single-quoted directories
cleanup_rogue_directories <- function() {
  base_dir <- get_base_results_dir()
  rogue_dirs <- c(
    file.path(base_dir, "'OMRS'"),
    file.path(base_dir, "omop_cdm")
  )
  for (r_dir in rogue_dirs) {
    if (dir.exists(r_dir)) {
      unlink(r_dir, recursive = TRUE, force = TRUE)
    }
  }
}

# Run immediate cleanup on initialization
cleanup_rogue_directories()

# ==============================================================================
# Metadata Patching Helper
# ==============================================================================
patch_dqd_metadata <- function(json_path) {
  if (!file.exists(json_path)) return(FALSE)
  tryCatch({
    data <- jsonlite::fromJSON(json_path)
    if (!is.null(data$cdmSourceName)) {
      data$cdmSourceName <- CDM_SOURCE_NAME
    }
    jsonlite::write_json(data, json_path, auto_unbox = TRUE, pretty = TRUE)
    return(TRUE)
  }, error = function(e) {
    message("Failed to patch metadata: ", e$message)
    return(FALSE)
  })
}

# ==============================================================================
# Endpoints
# ==============================================================================

#* Health check endpoint
#* @get /health
function() {
  list(
    status = "healthy",
    cdm_source = CDM_SOURCE_NAME,
    base_results_dir = get_base_results_dir(),
    timestamp = as.character(Sys.time())
  )
}

#* Run OHDSI's Data Quality Dashboard checks against the loaded CDM.
#* @param cdm_version Optional CDM version (default: "5.4")
#* @param cohort_table Optional cohort table name
#* @post /run-dqd
function(cdm_version = "5.4", cohort_table = "cohort", res) {
  tryCatch({
    cleanup_rogue_directories()
    connectionDetails <- get_connection_details()

    cat("Starting DQD checks at", as.character(Sys.time()), "\n")

    cdm_version_str  <- as.character(cdm_version)
    cohort_table_str <- as.character(cohort_table)

    base_results_dir <- get_base_results_dir()
    source_dir       <- get_source_dir()

    # Determine release key dynamically or fallback to YYYYMMDD
    sourceReleaseKey <- tryCatch({
      key <- suppressWarnings(AresIndexer::getSourceReleaseKey(connectionDetails, CDM_SCHEMA))
      basename(key)
    }, error = function(e) {
      format(Sys.Date(), "%Y%m%d")
    })

    releaseFolder <- sanitize_path_name(file.path(source_dir, sourceReleaseKey))
    dir.create(releaseFolder, showWarnings = FALSE, recursive = TRUE)

    # Prepare threshold CSV
    threshold_file_name <- sprintf("OMOP_CDMv%s_Field_Level.csv", cdm_version_str)
    defaultThresholdFile <- system.file("csv", threshold_file_name, package = "DataQualityDashboard")

    if (!file.exists(defaultThresholdFile)) {
      stop(sprintf("DQD threshold file not found for CDM version %s at: %s", cdm_version_str, defaultThresholdFile))
    }

    thresholds <- read.csv(defaultThresholdFile, stringsAsFactors = FALSE, colClasses = "character")

    if ("checkId" %in% names(thresholds) && "isForeignKeyNotes" %in% names(thresholds)) {
      target_idx <- which(thresholds$checkId == "field_fkclass_drug_strength_ingredient_concept_id")
      if (length(target_idx) > 0) {
        thresholds$isForeignKeyNotes[target_idx] <- "1"
      }
    }

    tempThresholdPath <- tempfile(fileext = ".csv")
    write.csv(thresholds, tempThresholdPath, row.names = FALSE)

    # Run DQD
    dqd_results <- DataQualityDashboard::executeDqChecks(
      connectionDetails = connectionDetails,
      cdmDatabaseSchema = CDM_SCHEMA,
      resultsDatabaseSchema = RESULTS_SCHEMA,
      vocabDatabaseSchema = VOCAB_SCHEMA,
      cdmSourceName = CDM_SOURCE_NAME,
      numThreads = as.integer(NUM_THREADS),
      sqlOnly = FALSE,
      cohortTable = cohort_table_str,
      cohortDatabaseSchema = CDM_SCHEMA,
      outputFolder = releaseFolder,
      cdmVersion = cdm_version_str,
      fieldCheckThresholdLoc = tempThresholdPath,
      outputFile = "dq-result.json",
      verboseMode = TRUE
    )

    primaryDqdPath <- file.path(releaseFolder, "dq-result.json")
    patch_dqd_metadata(primaryDqdPath)

    # Keep root dqd_latest.json up-to-date
    latestDqdPath <- file.path(base_results_dir, "dqd_latest.json")
    if (file.exists(primaryDqdPath)) {
      file.copy(primaryDqdPath, latestDqdPath, overwrite = TRUE)
    }

    # Parse pass/fail counts
    total_checks  <- 0
    failed_checks <- 0
    passed_checks <- 0

    if (!is.null(dqd_results) && !is.null(dqd_results$CheckResults)) {
      check_results <- as.data.frame(dqd_results$CheckResults)
      total_checks  <- nrow(check_results)

      if ("failed" %in% names(check_results)) {
        failed_checks <- sum(check_results$failed == 1 | check_results$failed == TRUE, na.rm = TRUE)
      } else if ("FAILED" %in% names(check_results)) {
        failed_checks <- sum(check_results$FAILED == 1 | check_results$FAILED == TRUE, na.rm = TRUE)
      }

      passed_checks <- total_checks - failed_checks
    }

    list(
      status = "succeeded",
      release_folder = releaseFolder,
      output_file = primaryDqdPath,
      total_checks = total_checks,
      failed_checks = failed_checks,
      passed_checks = passed_checks,
      timestamp = as.character(Sys.time())
    )
  }, error = function(e) {
    message("--- DQD EXECUTION FAILED ---")
    message(as.character(e$message))
    res$status <- 500
    list(
      status = "failed",
      error = as.character(e$message),
      timestamp = as.character(Sys.time())
    )
  })
}

#* Launch the interactive Data Quality Dashboard viewer UI in the background
#* @param cdm_schema Optional schema name (defaults to CDM_SCHEMA env var)
#* @post /launch-dqd-viewer
function(cdm_schema = CDM_SCHEMA, res) {
  tryCatch({
    base_dir <- get_base_results_dir()
    json_file_path <- file.path(base_dir, "dqd", "data", cdm_schema, "dq-result.json")

    if (!file.exists(json_file_path)) {
      json_file_path <- file.path(get_source_dir(), "20260820", "dq-result.json")
    }
    if (!file.exists(json_file_path)) {
      json_file_path <- file.path(base_dir, "dqd_latest.json")
    }

    if (!file.exists(json_file_path)) {
      res$status <- 404
      return(list(
        status = "error",
        message = sprintf("DQD results file not found at: %s. Run /run-dqd first.", json_file_path)
      ))
    }

    shiny_port <- as.numeric(Sys.getenv("SHINY_PORT", "3000"))
    shiny_host <- Sys.getenv("SHINY_HOST", "0.0.0.0")

    r_command <- sprintf(
      "library(DataQualityDashboard); Sys.setenv(SHINY_SERVER_BASE_PATH = '%s'); DataQualityDashboard::viewDqDashboard(jsonPath = '%s', launch.browser = FALSE, host = '%s', port = %d)",
      get_base_url(), json_file_path, shiny_host, shiny_port
    )

    system2("Rscript", args = c("-e", shQuote(r_command)), wait = FALSE)

    list(
      status = "succeeded",
      message = sprintf("DQD viewer background server started on port %d with base path %s", shiny_port, get_base_url())
    )
  }, error = function(e) {
    res$status <- 500
    list(
      status = "failed",
      error = as.character(e$message)
    )
  })
}

#* Run Achilles characterization and export static files for ARES.
#* @param cdm_version Optional CDM version (default: "5.4")
#* @post /run-achilles
function(cdm_version = "5.4", res) {
  tryCatch({
    cleanup_rogue_directories()
    connectionDetails <- get_connection_details()
    clean_source_name <- clean_env_string(CDM_SOURCE_NAME, "OMRS")

    base_results <- get_base_results_dir()
    source_dir   <- file.path(base_results, clean_source_name)

    cat("1. Running Achilles characterization...\n")
    Achilles::achilles(
      connectionDetails = connectionDetails,
      cdmDatabaseSchema = CDM_SCHEMA,
      resultsDatabaseSchema = RESULTS_SCHEMA,
      vocabDatabaseSchema = VOCAB_SCHEMA,
      sourceName = clean_source_name,
      numThreads = as.integer(NUM_THREADS),
      cdmVersion = as.character(cdm_version),
      smallCellCount = 0
    )

    cat("2. Exporting ARES-compatible CSV and JSON reports...\n")
    Achilles::exportToAres(
      connectionDetails = connectionDetails,
      cdmDatabaseSchema = CDM_SCHEMA,
      resultsDatabaseSchema = RESULTS_SCHEMA,
      vocabDatabaseSchema = VOCAB_SCHEMA,
      outputPath = base_results
    )

    sourceReleaseKey <- tryCatch({
      key <- suppressWarnings(AresIndexer::getSourceReleaseKey(connectionDetails, CDM_SCHEMA))
      basename(key)
    }, error = function(e) {
      format(Sys.Date(), "%Y%m%d")
    })

    releaseFolder <- sanitize_path_name(file.path(source_dir, sourceReleaseKey))

    cat("3. Writing achilles-performance.csv...\n")
    conn <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

    sql_perf <- sprintf("SELECT analysis_id, elapsed_seconds FROM %s.achilles_performance", RESULTS_SCHEMA)
    perf_data <- DatabaseConnector::querySql(conn, sql_perf)
    names(perf_data) <- tolower(names(perf_data))

    sql_count <- sprintf("SELECT COUNT(*) AS person_count FROM %s.person", CDM_SCHEMA)
    person_cnt <- tryCatch({
      cnt_df <- DatabaseConnector::querySql(conn, sql_count)
      as.numeric(cnt_df[[1]][1])
    }, error = function(e) 0)

    perf_data$person_count <- person_cnt

    write.csv(perf_data, file.path(releaseFolder, "achilles-performance.csv"), row.names = FALSE)
    write.csv(perf_data, file.path(source_dir, "achilles-performance.csv"), row.names = FALSE)

    # Sync DQD file automatically if available at root
    latest_dqd <- file.path(base_results, "dqd_latest.json")
    target_dqd <- file.path(releaseFolder, "dq-result.json")
    if (file.exists(latest_dqd)) {
      file.copy(latest_dqd, target_dqd, overwrite = TRUE)
      patch_dqd_metadata(target_dqd)
    }

    list(
      status = "succeeded",
      release_folder = releaseFolder,
      timestamp = as.character(Sys.time())
    )
  }, error = function(e) {
    res$status <- 500
    list(status = "failed", error = as.character(e$message))
  })
}

#* Run ARES network indexing over exported releases.
#* @post /run-ares-indexer
function(res) {
  tryCatch({
    cleanup_rogue_directories()
    base_results <- get_base_results_dir()
    clean_source <- clean_env_string(CDM_SOURCE_NAME, "OMRS")
    source_dir   <- file.path(base_results, clean_source)

    # List of source directories for network functions
    source_dirs <- list.dirs(base_results, recursive = FALSE)

    if (dir.exists(source_dir)) {
      release_dirs <- list.dirs(source_dir, recursive = FALSE)
      for (r_dir in release_dirs) {
        # Augment concept files with DQD details
        tryCatch({
          AresIndexer::augmentConceptFiles(releaseFolder = r_dir)
        }, error = function(e) {
          cat("Note on augmentConceptFiles for", r_dir, ":", conditionMessage(e), "\n")
        })
      }
    }

    cat("Building ARES network and metadata indexes...\n")

    # 1. Export query index
    tryCatch({
      AresIndexer::buildExportQueryIndex(base_results)
    }, error = function(e) {
      cat("Note on export query index:", conditionMessage(e), "\n")
    })

    # 2. Augment DQ files
    tryCatch({
      AresIndexer::augmentDataQualityFiles(sourceFolders = source_dirs)
    }, error = function(e) {
      cat("Note on augmentDataQualityFiles:", conditionMessage(e), "\n")
    })

    # 3. Source DQ delta
    tryCatch({
      AresIndexer::buildSourceDataQualityDelta(sourceFolders = source_dirs)
    }, error = function(e) {
      cat("Note on buildSourceDataQualityDelta:", conditionMessage(e), "\n")
    })

    # 4. Main network index
    AresIndexer::buildNetworkIndex(
      sourceFolders = source_dirs,
      outputFolder  = base_results
    )

    # 5. Data quality network index
    tryCatch({
      AresIndexer::buildDataQualityIndex(
        sourceFolders = source_dirs,
        outputFolder  = base_results
      )
    }, error = function(e) {
      cat("Warning during DQD index:", conditionMessage(e), "\n")
    })

    # 6. Unmapped source code index
    tryCatch({
      AresIndexer::buildNetworkUnmappedSourceCodeIndex(
        sourceFolders = source_dirs,
        outputFolder  = base_results
      )
    }, error = function(e) {
      cat("Note on buildNetworkUnmappedSourceCodeIndex:", conditionMessage(e), "\n")
    })

    list(
      status = "succeeded",
      results_dir = base_results,
      timestamp = as.character(Sys.time())
    )
  }, error = function(e) {
    res$status <- 500
    list(status = "failed", error = as.character(e$message))
  })
}

#* Debug endpoint to list all exported functions from AresIndexer
#* @get /ares-exports
function() {
  tryCatch({
    list(
      status = "succeeded",
      exports = getNamespaceExports("AresIndexer")
    )
  }, error = function(e) {
    list(
      status = "failed",
      error = as.character(e$message)
    )
  })
}