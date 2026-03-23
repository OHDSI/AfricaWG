#!/bin/bash
umask 000

export PGPASSWORD=$TARGET_PASS
MYSQL_USER="root"
MYSQL_PASSWORD="openmrs"
MYSQL_HOST="sqlmesh-db"
MYSQL_PORT="3306"
SOURCE_DB="omop_db"
TARGET_MYSQL_DB="public"
TARGET_PG_SCHEMA="public"
CONCEPTS_CSV_FILE="seed/CONCEPT.csv"
TEMP_DIR="tmp"

generate-mapper-placeholder-files(){
  python3 placeholder_files_generator.py
}
create-omop-postgres-schema(){
  echo "Dropping $TARGET_PG_SCHEMA Schema if already exists "
  psql -h "$TARGET_HOST" -U "$TARGET_USER" -d "$TARGET_DB" \
   -c "DROP SCHEMA IF EXISTS $TARGET_PG_SCHEMA CASCADE;"

  echo "Creating Omop postgres public schema and tables using ddl "
  psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" -d "$TARGET_DB" \
      -c "CREATE SCHEMA IF NOT EXISTS $TARGET_PG_SCHEMA;"

  echo "Importing Omop ddl structure"
  psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" -d "$TARGET_DB" \
      -f "omop-ddl/processed/ddl/01_OMOPCDM_postgresql_5.4_ddl.sql" 2>/dev/null || echo "Existing tables found, skipping DDL creation..."
}

sync-omrs-mappings(){
  python3 automated_athena_mappings.py
}

apply-sqlmesh-plan() {
  echo "Running SQLMesh plan..."
#  sqlmesh plan --no-prompts --auto-apply --restate-model '*'
  sqlmesh plan --no-prompts --auto-apply
  echo "SQLMesh plan completed."
}

materialize-mysql-views() {
  echo "Materializing views..."

  # === Create target MySQL DB if it doesn't exist ===
  echo "🛠️ Create target MySQL DB if it doesn't exist"
  mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_HOST -P $MYSQL_PORT --protocol=TCP -e "CREATE DATABASE IF NOT EXISTS \`$TARGET_MYSQL_DB\`;"

  #=== Step 1: Get all view names from the source DB ===
  echo "🔍 Fetching all views from '$SOURCE_DB'..."
  VIEW_LIST=$(mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_HOST -P $MYSQL_PORT --protocol=TCP -N -s -e "
  SELECT TABLE_NAME FROM information_schema.VIEWS
  WHERE TABLE_SCHEMA = '$SOURCE_DB';
  ")

  if [ -z "$VIEW_LIST" ]; then
    echo "❌ No views found in '$SOURCE_DB'. Nothing to do."
    exit 1
  fi

  echo "✅ Found views:"
  echo "$VIEW_LIST"

  # === Step 2: Materialize each view into the target MySQL DB ===
  for VIEW_NAME in $VIEW_LIST; do
  # 1. Skip empty strings
  [[ -z "$VIEW_NAME" ]] && continue

  echo "--------------------------------------------------------"
  echo "🔍 Processing: $VIEW_NAME"

  # 2. Duplicate Check: Predict ID column (e.g., measurement -> measurement_id)
  ID_COL_NAME="$(echo ${VIEW_NAME,,}_id)"
  # Run check
  DUP_COUNT=$(mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_HOST -P $MYSQL_PORT --protocol=TCP -N -s -e \
    "SELECT COUNT(*) FROM (SELECT \`$ID_COL_NAME\` FROM \`$SOURCE_DB\`.\`$VIEW_NAME\` GROUP BY 1 HAVING COUNT(*) > 1) AS x;" 2>/dev/null || echo "0")

  if [[ "${DUP_COUNT:-0}" -gt 0 ]]; then
    echo "🛑 ERROR: View '$VIEW_NAME' contains $DUP_COUNT duplicate IDs ($ID_COL_NAME)!"
    echo "   This WILL cause 'duplicate key value violates unique constraint' in pgloader."
  fi

  # 3. Materialize: Drop and Recreate
  echo "🚧 Materializing '$VIEW_NAME' into '$TARGET_MYSQL_DB'..."
  mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_HOST -P $MYSQL_PORT --protocol=TCP -e "
    DROP TABLE IF EXISTS \`$TARGET_MYSQL_DB\`.\`$VIEW_NAME\`;
    CREATE TABLE \`$TARGET_MYSQL_DB\`.\`$VIEW_NAME\` AS SELECT * FROM \`$SOURCE_DB\`.\`$VIEW_NAME\`;
  "

  # 4. Verify Materialization
  TABLE_EXISTS=$(mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_HOST -P $MYSQL_PORT --protocol=TCP -N -s -e "
    SELECT COUNT(*) FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = '$TARGET_MYSQL_DB' AND TABLE_NAME = '$VIEW_NAME';
  ")

  if [[ "${TABLE_EXISTS:-0}" -eq 1 ]]; then
    echo "✅ '$VIEW_NAME' successfully materialized."
  else
    echo "❌ Failed to materialize '$VIEW_NAME'."
  fi
done
  echo "Views materialized."
}

migrate-to-postgresql() {
  # Step 3.1: TRUNCATE clinical tables to prevent duplicate keys errors
  echo "Cleaning target tables in PostgreSQL to prevent duplicate key errors..."
   psql -h "$TARGET_HOST" -U "$TARGET_USER" -d "$TARGET_DB" \
   -c "TRUNCATE TABLE person, visit_occurrence, condition_occurrence, measurement, observation, observation_period, note, location, care_site, provider, death CASCADE;"

    #Step 3.2: Migrate the entire MySQL DB to PostgreSQL ===
  echo "🚚 Running pgloader to migrate entire database '$TARGET_MYSQL_DB' to PostgreSQL '$TARGET_DB' - $TARGET_PG_SCHEMA - schema"
  cat <<EOF > $TEMP_DIR/temp_pgloader.load
LOAD DATABASE
       FROM mysql://root:$SQLMESH_DB_ROOT_PASSWORD@sqlmesh-db:$MYSQL_PORT/$TARGET_MYSQL_DB
       INTO postgresql://$TARGET_USER:$TARGET_PASS@$TARGET_HOST:$TARGET_PORT/$TARGET_DB

        WITH include no drop,
             create tables,
             create indexes,
             reset sequences,
             data only,
             truncate

        CAST type datetime to "timestamp without time zone" drop default drop not null,
             type date to date,
             type int to integer;
EOF
  pgloader $TEMP_DIR/temp_pgloader.load

  echo "✅ Migration complete: All materialized views are now in PostgreSQL database '$TARGET_DB'."
}

import-omop-concepts() {
 echo "Temporarily dropping Foreign Key constraints to allow data load..."

   psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" -c "
       DO \$\$ DECLARE
           r RECORD;
       BEGIN
           -- Drop all Foreign Keys
           FOR r IN (SELECT constraint_name, table_name
                     FROM information_schema.table_constraints
                     WHERE constraint_type = 'FOREIGN KEY' AND table_schema = '$TARGET_PG_SCHEMA') LOOP
               EXECUTE 'ALTER TABLE ' || r.table_name || ' DROP CONSTRAINT ' || r.constraint_name;
           END LOOP;

           -- Drop all Primary Keys
           FOR r IN (SELECT constraint_name, table_name
                     FROM information_schema.table_constraints
                     WHERE constraint_type = 'PRIMARY KEY' AND table_schema = '$TARGET_PG_SCHEMA') LOOP
               EXECUTE 'ALTER TABLE ' || r.table_name || ' DROP CONSTRAINT ' || r.constraint_name;
           END LOOP;
       END \$\$;"

  # Clean existing concept data before re-importing to prevent duplicates
  echo "Truncating existing vocabulary tables..."
  psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" -c "
      TRUNCATE TABLE concept_relationship, concept_synonym, concept_ancestor, drug_strength,
                     vocabulary, domain, concept_class, relationship, concept CASCADE;"

  echo "Importing concepts and relationships..."
  # 1. Standard Vocab Tables
  for table in concept_class domain vocabulary relationship; do
      psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" \
      -c "\copy $table FROM 'seed/${table^^}.csv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true);"
  done

  # 2. Main Concept Table
  sed 's/"/""/g' $CONCEPTS_CSV_FILE > $TEMP_DIR/escaped_concepts.tmp.csv
  psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" \
    -c "\copy concept FROM '$TEMP_DIR/escaped_concepts.tmp.csv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true);"

  # 3. Optional Synonyms & Drug Strength
  for opt_table in CONCEPT_SYNONYM DRUG_STRENGTH; do
      if [ -f "seed/$opt_table.csv" ]; then
        echo "Preparing and loading ${opt_table,,}..."
        if [ "$opt_table" == "CONCEPT_SYNONYM" ]; then
            psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" \
            -c "ALTER TABLE concept_synonym ALTER COLUMN concept_synonym_name TYPE TEXT;"
        fi
        psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" \
        -c "\copy ${opt_table,,} FROM 'seed/$opt_table.csv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, QUOTE E'\b');"
      fi
  done

  # 4. Large Mapping & Hierarchy Tables
  echo "Importing Relationships and Ancestors..."
  psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" \
  -c "\copy concept_relationship FROM 'seed/CONCEPT_RELATIONSHIP.csv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true);"

  psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" \
  -c "\copy concept_ancestor FROM 'seed/CONCEPT_ANCESTOR.csv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true);"

  # === CRITICAL CLEANUP: Fixes Step 5 Errors ===
  echo "Cleaning up orphan records (Foreign Key Fix)..."
  psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" <<EOF
    -- Create a temporary index to make lookups instant
    CREATE INDEX IF NOT EXISTS idx_temp_concept_id ON concept(concept_id);
    ANALYZE concept;

    -- Delete using a correlated subquery (much faster than NOT IN)
    DELETE FROM concept_relationship r
    WHERE NOT EXISTS (SELECT 1 FROM concept c WHERE c.concept_id = r.concept_id_1)
       OR NOT EXISTS (SELECT 1 FROM concept c WHERE c.concept_id = r.concept_id_2);

    DELETE FROM concept_synonym s
    WHERE NOT EXISTS (SELECT 1 FROM concept c WHERE c.concept_id = s.concept_id);

    DELETE FROM concept_ancestor a
    WHERE NOT EXISTS (SELECT 1 FROM concept c WHERE c.concept_id = a.ancestor_concept_id)
       OR NOT EXISTS (SELECT 1 FROM concept c WHERE c.concept_id = a.descendant_concept_id);

    DELETE FROM drug_strength d
    WHERE NOT EXISTS (SELECT 1 FROM concept c WHERE c.concept_id = d.drug_concept_id)
       OR NOT EXISTS (SELECT 1 FROM concept c WHERE c.concept_id = d.ingredient_concept_id);

    -- Drop the temp index (Step 5 will create the official ones)
    DROP INDEX idx_temp_concept_id;
EOF
  echo "📊 Optimizing database statistics..."
  psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" -c "VACUUM ANALYZE;"

  echo "✅ Concepts imported and cleaned successfully"
}

apply-omop-constraints() {
  echo "Cleaning up old indices and constraints..."
  psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" -c "
      DO \$\$ DECLARE
          r RECORD;
      BEGIN
          -- Drop all indices in the $TARGET_PG_SCHEMA schema to avoid 'already exists' errors
          FOR r IN (SELECT indexname FROM pg_indexes WHERE schemaname = '$TARGET_PG_SCHEMA') LOOP
              EXECUTE 'DROP INDEX IF EXISTS ' || r.indexname || ' CASCADE';
          END LOOP;
      END \$\$;"

  echo "🔗 Connecting to PostgreSQL and executing constraint scripts..."
  for sql_file in omop-ddl/processed/constraints/*.sql; do
    echo "⚙️  Executing $sql_file..."
    psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" -f "$sql_file"
  done

  echo "✅ All constraint scripts executed."
}

populate-cdm-source() {
  local sql_file="${TEMP_DIR}/cdm_source.sql"

  : "${CDM_SOURCE_NAME:=OpenMRS OMOP CDM}"
  : "${CDM_SOURCE_ABBR:=OMRS}"
  : "${CDM_HOLDER:=OpenMRS Community}"
  : "${CDM_SOURCE_DESC:=OMOP CDM instance generated from OpenMRS data.}"
  : "${CDM_DOC_REF:=https://openmrs.org}"
  : "${CDM_ETL_REF:=https://github.com/OHDSI/AfricaWG.git}"
  : "${CDM_VERSION:=5.4.0}"
  : "${VOCAB_VERSION:=v5.0}"

  mkdir -p "$(dirname "$sql_file")"

  cat > "$sql_file" <<'SQL'
\set ON_ERROR_STOP on
BEGIN;
TRUNCATE TABLE public.cdm_source;
INSERT INTO public.cdm_source (
  cdm_source_name,
  cdm_source_abbreviation,
  cdm_holder,
  source_description,
  source_documentation_reference,
  cdm_etl_reference,
  source_release_date,
  cdm_release_date,
  cdm_version,
  cdm_version_concept_id,
  vocabulary_version
) VALUES (
  :'cdm_source_name',
  :'cdm_source_abbr',
  :'cdm_holder',
  :'cdm_source_desc',
  :'cdm_doc_ref',
  :'cdm_etl_ref',
  CURRENT_DATE,
  CURRENT_DATE,
  :'cdm_version',
  1,
  :'vocab_version'
);
COMMIT;
SQL

  psql -U "$TARGET_USER" -h "$TARGET_HOST" -p "$TARGET_PORT" -d "$TARGET_DB" \
    -v cdm_source_name="$CDM_SOURCE_NAME" \
    -v cdm_source_abbr="$CDM_SOURCE_ABBR" \
    -v cdm_holder="$CDM_HOLDER" \
    -v cdm_source_desc="$CDM_SOURCE_DESC" \
    -v cdm_doc_ref="$CDM_DOC_REF" \
    -v cdm_etl_ref="$CDM_ETL_REF" \
    -v cdm_version="$CDM_VERSION" \
    -v vocab_version="$VOCAB_VERSION" \
    -f "$sql_file"
}

automated-mapping-summary-report(){
    python3 automated_mapping_summary.py
}

command="$1"
shift

echo "DEBUG: received command: $command"
echo "DEBUG: all args: $@"

# Create tmp directory if it doesn't exist
mkdir -p "$TEMP_DIR"

case "$command" in
 generate-mapper-placeholder-files)
   generate-mapper-placeholder-files
   ;;
  create-omop-postgres-schema)
    create-omop-postgres-schema
    ;;
  sync-omrs-mappings)
    sync-omrs-mappings
    ;;
  apply-sqlmesh-plan)
    apply-sqlmesh-plan
    ;;
  materialize-mysql-views)
   materialize-mysql-views
    ;;
  migrate-to-postgresql)
    migrate-to-postgresql
    ;;
  import-omop-concepts)
    import-omop-concepts
    ;;
  apply-omop-constraints)
    apply-omop-constraints
    ;;
  populate-cdm-source)
    populate-cdm-source
    ;;
  automated-mapping-summary-report)
    automated-mapping-summary-report
    ;;
  run-full-pipeline)
    echo "🚀 Starting Full OMRS - OMOP/CDM Etl Pipeline"
    echo "Step 1/11"
    generate-mapper-placeholder-files
    echo "Step 2/11"
    create-omop-postgres-schema
    echo "Step 3/11"
    import-omop-concepts
    echo "Step 4/11"
    sync-omrs-mappings
    echo "Step 5/11"
    apply-omop-constraints
    echo "Step 6/11"
    populate-cdm-source
    echo "Step 7/11"
    apply-sqlmesh-plan
    echo "Step 8/11"
    materialize-mysql-views
    echo "Step 9/11"
    migrate-to-postgresql
    echo "Step 10/11"
    populate-cdm-source
    echo "Step 11/11"
    generate_mapping_report
    echo "✅ Full Pipeline Completed Successfully!"
    ;;
  *)
   echo "Unknown command: $command"
    echo "Usage: $0 {generate-mapper-placeholder-files|create-omop-postgres-schema|import-omop-concepts
    |sync-omrs-mappings|apply-omop-constraints|populate-cdm-source|apply-sqlmesh-plan|materialize-mysql-views
    |migrate-to-postgresql|populate-cdm-source|generate_mapping_report}"
    exit 1
    ;;
esac

# Remove temp directory
rm -rf "$TEMP_DIR"
