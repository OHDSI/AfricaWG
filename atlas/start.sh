#!/bin/sh

# Start WebAPI in the background
echo "Starting WebAPI..."
java ${DEFAULT_JAVA_OPTS} ${JAVA_OPTS} \
    -cp ".:WebAPI.jar:WEB-INF/lib/*.jar${CLASSPATH}" \
    org.springframework.boot.loader.WarLauncher &

# Wait for WebAPI to start (adjust as needed)
echo "Sleeping 10s to allow WebAPI to initialize..."
sleep 20

# Wait for WebAPI tables to exist
echo "Waiting for WebAPI schema 'ohdsi' and table 'sec_user'..."
until python3 - <<END
import psycopg2
import sys

try:
    conn = psycopg2.connect(host='omop-db', dbname='omop', user='omop', password='omop')
    cur = conn.cursor()
    # Check if sec_user table exists
    cur.execute("""
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'ohdsi'
          AND table_name = 'sec_user'
        LIMIT 1;
    """)
    if cur.fetchone() is None:
        sys.exit(1)
except Exception:
    sys.exit(1)
END
do
    echo "WebAPI tables not ready, waiting 5s..."
    sleep 5
done

# Run Python init
echo "Running Python init..."
python3 /init_webapi.py

# Wait for WebAPI process to finish
wait