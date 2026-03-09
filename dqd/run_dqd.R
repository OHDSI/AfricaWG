args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  stop("Please provide an argument: 'run' or 'view'")
}

mode <- args[[1]]

source("/postprocessing/init.R")

log_message <- function(msg, level = "INFO") {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("[%s] [%s] %s\n", timestamp, level, msg))
}

splitOrEmpty <- function(x) {
  if (is.na(x) || x == "" || x == "NULL") return(character(0))
  strsplit(x, ",", fixed = TRUE)[[1]]
}

if (mode == "run") {
#   source("/postprocessing/init.R")
  log_message("Initializing DQD wrapper configuration...")
  envVarNames <- list(
    "DQD_NUM_THREADS",
    "DQD_SQL_ONLY",
    "DQD_SQL_ONLY_UNION_COUNT",
    "DQD_SQL_ONLY_INCREMENTAL_INSERT",
    "DQD_VERBOSE_MODE",
    "DQD_WRITE_TO_TABLE",
    "DQD_WRITE_TABLE_NAME",
    "DQD_WRITE_TO_CSV",
    "DQD_CSV_FILE",
    "DQD_CHECK_LEVELS",
    "DQD_CHECK_NAMES",
    "DQD_COHORT_DEFINITION_ID",
    "DQD_COHORT_DATABASE_SCHEMA",
    "DQD_COHORT_TABLE_NAME",
    "DQD_TABLES_TO_EXCLUDE",
    "DQD_TABLE_CHECK_THRESHOLD_LOC",
    "DQD_FIELD_CHECK_THRESHOLD_LOC",
    "DQD_CONCEPT_CHECK_THRESHOLD_LOC"
  )

  jobConfig <- as.list(Sys.getenv(envVarNames, unset = NA))

  outputFolder <- file.path("/postprocessing",
                            "dqd",
                            "data",
                            cdmConfig$CDM_DATABASE_SCHEMA)

  if (!file.exists(outputFolder)) {
    log_message(sprintf("Creating output directory: %s", outputFolder))
    dir.create(path = outputFolder, recursive = TRUE)
  }

  if (jobConfig$DQD_COHORT_DEFINITION_ID == "") {
    jobConfig$DQD_COHORT_DEFINITION_ID <- c()
  }

  checkNames <- splitOrEmpty(jobConfig$DQD_CHECK_NAMES)
     if (length(checkNames) == 0) {
         checkNames <- c(
             "cdmTable", "cdmField", "isRequired", "cdmDatatype", "isPrimaryKey",
             "isForeignKey", "fkDomain", "fkClass", "isStandardValidConcept",
             "measurePersonCompleteness", "plausibleValueLow", "plausibleValueHigh",
             "plausibleBeforeDeath", "plausibleAfterBirth",
             "plausibleStartBeforeEnd", "plausibleGenderUseDescendants",
             "measureConditionEraCompleteness","measureObservationPeriodOverlap",
             "measureValueCompleteness","standardConceptRecordCompleteness",
             "sourceConceptRecordCompleteness","sourceValueCompleteness",
              "withinVisitDates",
             "plausibleUnitConceptIds"

         )
         log_message("No DQD_CHECK_NAMES provided. Using modern standard defaults.")
     }

log_message("Starting DQD execution (mode: run)...")

tryCatch({
  result <- DataQualityDashboard::executeDqChecks(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cdmConfig$CDM_DATABASE_SCHEMA,
    resultsDatabaseSchema = cdmConfig$RESULTS_DATABASE_SCHEMA,
    vocabDatabaseSchema = cdmConfig$VOCAB_DATABASE_SCHEMA,
    cdmSourceName = cdmConfig$CDM_SOURCE_NAME,
    numThreads = as.numeric(jobConfig$DQD_NUM_THREADS),
    sqlOnly = as.logical(jobConfig$DQD_SQL_ONLY),
    sqlOnlyUnionCount = as.numeric(jobConfig$DQD_SQL_ONLY_UNION_COUNT),
    sqlOnlyIncrementalInsert = as.logical(jobConfig$DQD_SQL_ONLY_INCREMENTAL_INSERT),
    outputFolder = outputFolder,
    outputFile = "dq-result_camel.json",
    verboseMode = as.logical(jobConfig$DQD_VERBOSE_MODE),
    writeToTable = as.logical(jobConfig$DQD_WRITE_TO_TABLE),
    writeTableName = jobConfig$DQD_WRITE_TABLE_NAME,
    writeToCsv = as.logical(jobConfig$DQD_WRITE_TO_CSV),
    csvFile = jobConfig$DQD_CSV_FILE,
    checkLevels =  splitOrEmpty(jobConfig$DQD_CHECK_LEVELS),
    checkNames = checkNames,
    cohortDefinitionId = jobConfig$DQD_COHORT_DEFINITION_ID,
    cohortDatabaseSchema = jobConfig$DQD_COHORT_DATABASE_SCHEMA,
    cohortTableName = jobConfig$DQD_COHORT_TABLE_NAME,
    tablesToExclude = splitOrEmpty(jobConfig$DQD_TABLES_TO_EXCLUDE),
    cdmVersion = cdmConfig$CDM_VERSION,
    tableCheckThresholdLoc = jobConfig$DQD_TABLE_CHECK_THRESHOLD_LOC,
    fieldCheckThresholdLoc = jobConfig$DQD_FIELD_CHECK_THRESHOLD_LOC,
    conceptCheckThresholdLoc = jobConfig$DQD_CONCEPT_CHECK_THRESHOLD_LOC
  )

  DataQualityDashboard::convertJsonResultsFileCase(
    jsonFilePath = file.path(outputFolder, "dq-result_camel.json"),
    writeToFile = TRUE,
    outputFolder = outputFolder,
    outputFile = "dq-result.json",
    targetCase = "snake"
  )

 log_message("Success: DQD results generated and converted.")

}, error = function(e) {
    log_message(sprintf("CRITICAL ERROR: %s", e$message), level = "ERROR")
    quit(status = 1)
  })


} else if (mode == "view") {
  log_message("Launching DQD viewer (mode: view)...")

  jsonFilePath <- file.path("/postprocessing",
                            "dqd",
                            "data",
                            cdmConfig$CDM_DATABASE_SCHEMA,
                            "dq-result.json")

  if (!file.exists(jsonFilePath)) {
       log_message(sprintf("Error: Results file not found at %s", jsonFilePath), level = "ERROR")
       quit(status = 1)
  }

  DataQualityDashboard::viewDqDashboard(
        jsonFilePath,
        launch.browser = FALSE,
        host = "0.0.0.0",
        port = 3000)
} else {
  stop("Invalid argument. Use 'run' or 'view'.")
}
