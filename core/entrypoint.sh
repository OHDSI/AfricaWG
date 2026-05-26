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
TARGET_DB="postgres"
TEMP_DIR="tmp"

generate-mapper-placeholder-files(){
  python3 placeholder_files_generator.py
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
      -c "SET search_path TO $TARGET_PG_SCHEMA; TRUNCATE TABLE person, visit_occurrence, condition_occurrence, measurement, observation, observation_period, note, location, care_site, provider, death CASCADE;"

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
  automated-mapping-summary-report)
    automated-mapping-summary-report
    ;;
  run-full-pipeline)
    echo "🚀 Starting Full OMRS - OMOP/CDM Etl Pipeline"
    echo "Step 1/11"
    generate-mapper-placeholder-files
    echo "Step 4/11"
    sync-omrs-mappings
    echo "Step 7/11"
    apply-sqlmesh-plan
    echo "Step 8/11"
    materialize-mysql-views
    echo "Step 9/11"
    migrate-to-postgresql
    echo "Step 11/11"
    generate_mapping_report
    echo "✅ Full Pipeline Completed Successfully!"
    ;;
  *)
   echo "Unknown command: $command"
    echo "Usage: $0 {generate-mapper-placeholder-files
    |sync-omrs-mappings|apply-sqlmesh-plan|materialize-mysql-views
    |migrate-to-postgresql|generate_mapping_report}"
    exit 1
    ;;
esac

# Remove temp directory
rm -rf "$TEMP_DIR"
