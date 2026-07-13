#!/usr/bin/env bash
set -euo pipefail

# Regenerates the WebAPI results and OMOP CDM SQL (DDL) artifacts and writes them under vendor/
# Inputs via env (optional): (defaults are set in the Makefile)
#   WEBAPI_VERSION
#   CDM_VERSION
#   SQLRENDER_VERSION
#   SQLRENDER_JAR (optional: path to a pre-downloaded SqlRender.jar)

# Resolve project root first (used below to read Makefile defaults)
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Prefer Makefile's WEBAPI_VERSION when not provided via environment
if [ -z "${WEBAPI_VERSION:-}" ]; then
  MF="$ROOT_DIR/Makefile"
  if [ -f "$MF" ]; then
    MF_WVER=$(sed -n 's/^WEBAPI_VERSION[[:space:]]*[?:]*=[[:space:]]*//p' "$MF" | head -n1 | tr -d '[:space:]')
    if [ -n "$MF_WVER" ]; then
      WEBAPI_VERSION="$MF_WVER"
    fi
  fi
fi
# Require WEBAPI_VERSION to be set via env or Makefile
if [ -z "${WEBAPI_VERSION:-}" ]; then
  echo "ERROR: WEBAPI_VERSION is not set. Define it in the Makefile (e.g., 'WEBAPI_VERSION?=v2.15.0') or export it in the environment before running this script." >&2
  exit 2
fi

# Prefer Makefile's SQLRENDER_VERSION when not provided via environment
if [ -z "${SQLRENDER_VERSION:-}" ]; then
  MF="$ROOT_DIR/Makefile"
  if [ -f "$MF" ]; then
    MF_VER=$(sed -n 's/^SQLRENDER_VERSION[[:space:]]*[?:]*=[[:space:]]*//p' "$MF" | head -n1 | tr -d '[:space:]')
    if [ -n "$MF_VER" ]; then
      SQLRENDER_VERSION="$MF_VER"
    fi
  fi
fi
# Require SQLRENDER_VERSION to be set via env or Makefile
if [ -z "${SQLRENDER_VERSION:-}" ]; then
  echo "ERROR: SQLRENDER_VERSION is not set. Define it in the Makefile (e.g., 'SQLRENDER_VERSION?=1.16.1') or export it in the environment before running this script." >&2
  exit 2
fi

# SqlRender artifact details and repo base (override if needed)
SQLRENDER_GROUP_ID=${SQLRENDER_GROUP_ID:-org.ohdsi.sql}
SQLRENDER_ARTIFACT_ID=${SQLRENDER_ARTIFACT_ID:-SqlRender}
OHDSI_NEXUS_BASE=${OHDSI_NEXUS_BASE:-http://repo.ohdsi.org:8085/nexus/repository/releases}

# temporary working directory and output vendor directory
TMP_DIR="${ROOT_DIR}/.tmp_webapi_gen"
VENDOR_DIR="${ROOT_DIR}/vendor"

command -v git >/dev/null || { echo "git is required"; exit 2; }
command -v java >/dev/null || { echo "java (JRE) is required"; exit 2; }

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR" "$VENDOR_DIR"

echo "Cloning OHDSI/WebAPI @ ${WEBAPI_VERSION}..."
GIT_CLONE_CMD=(git -C "$TMP_DIR" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 clone --branch "$WEBAPI_VERSION" --depth 1 https://github.com/OHDSI/WebAPI)
if command -v timeout >/dev/null; then
  timeout 240s "${GIT_CLONE_CMD[@]}" >/dev/null || { echo "git clone timed out or failed" >&2; exit 4; }
else
  "${GIT_CLONE_CMD[@]}" >/dev/null || { echo "git clone failed" >&2; exit 4; }
fi

echo "Locating SqlRender ${SQLRENDER_VERSION}..."
# 1) Provided JAR via env
if [ -n "${SQLRENDER_JAR:-}" ] && [ -f "$SQLRENDER_JAR" ]; then
  echo "Using SQLRENDER_JAR: $SQLRENDER_JAR"
  cp "$SQLRENDER_JAR" "$TMP_DIR/SqlRender.jar"
else
  # 2) Local Maven cache (no network)
  GROUP_PATH=${SQLRENDER_GROUP_ID//./\/}
  LOCAL_JAR="${HOME}/.m2/repository/${GROUP_PATH}/${SQLRENDER_ARTIFACT_ID}/${SQLRENDER_VERSION}/${SQLRENDER_ARTIFACT_ID}-${SQLRENDER_VERSION}.jar"
  if [ -f "$LOCAL_JAR" ]; then
    echo "Using SqlRender from local Maven cache: $LOCAL_JAR"
    cp "$LOCAL_JAR" "$TMP_DIR/SqlRender.jar"
  fi

  # 3) Maven fetch from OHDSI Nexus (8085)
  if [ ! -s "$TMP_DIR/SqlRender.jar" ] && command -v mvn >/dev/null; then
    echo "Fetching SqlRender via Maven from OHDSI Nexus (8085)..."
  MVN_GET=(mvn -q -U org.apache.maven.plugins:maven-dependency-plugin:3.6.1:get -Dtransitive=false -DrepoUrl=${OHDSI_NEXUS_BASE} -DremoteRepositories=ohdsi::default::${OHDSI_NEXUS_BASE})
    "${MVN_GET[@]}" -Dartifact=${SQLRENDER_GROUP_ID}:${SQLRENDER_ARTIFACT_ID}:${SQLRENDER_VERSION} || true
    if [ -f "$LOCAL_JAR" ]; then
      echo "Resolved via Maven: $LOCAL_JAR"
      cp "$LOCAL_JAR" "$TMP_DIR/SqlRender.jar"
    fi
  fi

  # 4) Direct download from OHDSI Nexus (8085) if still missing or Maven unavailable
  if [ ! -s "$TMP_DIR/SqlRender.jar" ]; then
    if command -v mvn >/dev/null; then
      echo "Maven fetch failed; falling back to direct download from OHDSI Nexus (8085)..."
    else
      echo "Maven not available; direct download from OHDSI Nexus (8085)..."
    fi
    CANON_URL="${OHDSI_NEXUS_BASE}/${GROUP_PATH}/${SQLRENDER_ARTIFACT_ID}/${SQLRENDER_VERSION}/${SQLRENDER_ARTIFACT_ID}-${SQLRENDER_VERSION}.jar"
    if command -v curl >/dev/null; then
      curl -fsSL --max-time 90 --retry 2 "$CANON_URL" -o "$TMP_DIR/SqlRender.jar" || true
    elif command -v wget >/dev/null; then
      wget -q --timeout=90 --tries=2 "$CANON_URL" -O "$TMP_DIR/SqlRender.jar" || true
    else
      echo "curl/wget not available to fetch SqlRender" >&2
      exit 2
    fi
  fi
fi

# Ensure we have the jar before proceeding
if [ ! -s "$TMP_DIR/SqlRender.jar" ]; then
  echo "Failed to retrieve SqlRender ${SQLRENDER_VERSION} from OHDSI Nexus (8085)." >&2
  exit 3
fi

echo "Concatenating results schema (deterministic order)..."
pushd "$TMP_DIR/WebAPI/src/main/resources/ddl/results" >/dev/null
find . -maxdepth 1 -type f -not -regex '.*\(index\|init\|hive\|impala\).*' | sort | xargs cat > "$TMP_DIR/results_ohdisql.ddl"
find . -maxdepth 1 -type f \( -name '*init*.sql' ! -name '*hive*.sql' \) | sort | xargs cat >> "$TMP_DIR/results_ohdisql.ddl"
find . -maxdepth 1 -type f -name '*index*.sql' | sort | xargs cat >> "$TMP_DIR/results_ohdisql.ddl"
popd >/dev/null

echo "Rendering and translating to PostgreSQL..."
java -jar "$TMP_DIR/SqlRender.jar" \
  "$TMP_DIR/results_ohdisql.ddl" \
  "$TMP_DIR/results_postgresql.ddl" \
  -translate postgresql \
  -render results_schema cdm_results vocab_schema public

echo "Building WebAPI baseline SQL..."
pushd "$TMP_DIR/WebAPI/src/main/resources/db/migration/postgresql" >/dev/null
echo 'set search_path=webapi;' > "$TMP_DIR/set_search_path_webapi.sql"
cat \
  "$TMP_DIR/set_search_path_webapi.sql" \
  V1.0.0.1__schema-create_spring_batch.sql \
  V1.0.0.2__schema-create_jpa.sql \
  V1.0.0.3__cohort_definition_persistence.sql \
  V1.0.0.3.1__cohort_generation.sql \
  V1.0.0.3.2__alter_foreign_keys.sql \
  V1.0.0.4__cohort_analysis_results.sql \
  V1.0.0.4.1__heracles_heel.sql \
  V1.0.0.4.2__measurement_types.sql \
  V1.0.0.4.3__heracles_index.sql \
  V1.0.0.5__feasability_tables.sql \
  V1.0.0.5.1__alter_foreign_keys.sql \
  V1.0.0.6.1__schema-create_laertes.sql \
  V1.0.0.6.2__schema-create_laertes.sql \
  V1.0.0.6.3__schema-create_laertes.sql \
  V1.0.0.6.4__schema-create_laertes.sql \
  V1.0.0.6.5__schema-create_penelope_laertes.sql \
  V1.0.0.7.0__sources.sql.sql \
  V1.0.0.7.1__cohort_multihomed_support.sql \
  V1.0.0.7.2__feasability_multihomed_support.sql.sql \
  V1.0.0.8__heracles_data.sql \
  V1.0.0.9__shiro_security.sql \
  V1.0.0.9.1__shiro_security-initial_values.sql \
  V1.0.1.0__conceptsets.sql \
  V1.0.1.1__penelope.sql \
  V1.0.1.1.1__penelope_data.sql \
  V1.0.1.2__conceptset_negative_controls.sql \
  V1.0.1.3__conceptset_generation_info.sql \
  V1.0.2.0__cohort_feasiblity.sql \
  V1.0.3.1__comparative_cohort_analysis.sql \
  V1.0.4.0__ir_analysis.sql \
  V1.0.4.1__ir_dist.sql \
  V1.0.5.0__rename_system_user_to_anonymous.sql \
  V1.0.6.0__schema-create-plp.sql \
  V1.0.6.0.1__schema-add-analysis_execution_password.sql \
  V1.0.7.0__alter_cohort_generation_info.sql \
  V1.0.8.0__cohort_features_results.sql \
  V1.0.9.0__data-permissions.sql \
  V1.0.10.0__data-atlas-user.sql \
  V1.0.11.0__data-cohortanalysis-permission.sql \
  V1.0.11.1__schema-executions.sql \
  V2.2.0.20180202143000__delete-unnecessary-admin-permissions.sql \
  V2.2.0.20180215143000__remove_password.sql \
  V2.2.5.20180212152023__concept-sets-author.sql \
  > "$TMP_DIR/webapi_baseline_V2.2.5.20180212152023_postgresql.sql"
sed -i 's/\${ohdsiSchema}/webapi/g' "$TMP_DIR/webapi_baseline_V2.2.5.20180212152023_postgresql.sql"
popd >/dev/null

echo "Writing outputs to ${VENDOR_DIR}/webapi..."
cp "$TMP_DIR/results_postgresql.ddl" "$VENDOR_DIR/webapi/results_postgresql.ddl"
cp "$TMP_DIR/webapi_baseline_V2.2.5.20180212152023_postgresql.sql" "$VENDOR_DIR/webapi/webapi_baseline_V2.2.5.20180212152023_postgresql.sql"

# -------------------------------------------------------------
# CDM DDL retrieval based on CDM_VERSION (exported via Makefile)
# -------------------------------------------------------------
if [ -z "${CDM_VERSION:-}" ]; then
  echo "ERROR: CDM_VERSION is not set (export it or add to Makefile)." >&2
  exit 2
fi

# Example: CDM_VERSION=v5.4.2 -> release asset path uses v5.4.2, file named OMOPCDM_v5.4.zip
CDM_MAJOR_MINOR=$(echo "$CDM_VERSION" | sed -E 's/^v([0-9]+\.[0-9]+).*/\1/')
CDM_VERSION_STRIPPED=${CDM_VERSION#v}
CDM_TMP_DIR="$TMP_DIR/cdm_${CDM_VERSION}"
CDM_ZIP_NAME="OMOPCDM_v${CDM_MAJOR_MINOR}.zip"
CDM_ZIP_PATH="$CDM_TMP_DIR/$CDM_ZIP_NAME"
mkdir -p "$CDM_TMP_DIR"
CDM_URL="https://github.com/OHDSI/CommonDataModel/releases/download/${CDM_VERSION}/${CDM_ZIP_NAME}"

echo "Fetching CDM DDL from ${CDM_URL} ..."
if command -v wget >/dev/null; then
  wget -q -O "$CDM_ZIP_PATH" "$CDM_URL" || { echo "Failed to wget $CDM_URL" >&2; exit 5; }
elif command -v curl >/dev/null; then
  curl -fsSL "$CDM_URL" -o "$CDM_ZIP_PATH" || { echo "Failed to curl $CDM_URL" >&2; exit 5; }
else
  echo "Neither wget nor curl available to download CDM zip." >&2
  exit 5
fi

unzip -q -o "$CDM_ZIP_PATH" -d "$CDM_TMP_DIR" || { echo "Failed to unzip $CDM_ZIP_PATH" >&2; exit 6; }

# Derive expected relative path: <major.minor>/postgres/postgresql_<major.minor>_ddl.sql
REL_DIR="${CDM_MAJOR_MINOR}/postgresql"
POSTGRES_DDL_SRC="${CDM_TMP_DIR}/${REL_DIR}/OMOPCDM_postgresql_${CDM_MAJOR_MINOR}_ddl.sql"
if [ ! -f "$POSTGRES_DDL_SRC" ]; then
  echo "ERROR: Expected DDL file not found at $POSTGRES_DDL_SRC" >&2
  exit 7
fi

echo "Staging OMOP CDM DDL for SqlRender translation..."
cp "$POSTGRES_DDL_SRC" "$TMP_DIR/omop_cdm_ohdisql_ddl.sql"

echo "Translating OMOP CDM DDL with SqlRender to PostgreSQL..."
java -jar "$TMP_DIR/SqlRender.jar" \
  "$TMP_DIR/omop_cdm_ohdisql_ddl.sql" \
  "$TMP_DIR/omop_cdm_postgresql_ddl.sql" \
  -translate postgresql \
  -render cdmDatabaseSchema public \
  || { echo "SqlRender translation failed for CDM DDL" >&2; exit 8; }

# Use the translated output as the vendored Postgres DDL consumed by the Dockerfile build (step 020)
cp "$TMP_DIR/omop_cdm_postgresql_ddl.sql" "$VENDOR_DIR/cdm/omop_cdm_postgres_ddl.sql"
echo "Translated OMOP CDM Postgres DDL saved to vendor/cdm/omop_cdm_postgres_ddl.sql"

echo "Done. Files written:"
ls -lR "$VENDOR_DIR"
