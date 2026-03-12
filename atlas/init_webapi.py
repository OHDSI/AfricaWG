import time
import psycopg2
from psycopg2.extras import execute_batch

DB_HOST = "omop-db"
DB_NAME = "omop"
DB_USER = "omop"
DB_PASS = "omop"

SQL = """
-- ==========================================
-- 1. Create admin user if not exists
-- ==========================================
INSERT INTO ohdsi.sec_user (login, name)
SELECT 'admin', 'Admin User'
WHERE NOT EXISTS (
    SELECT 1 FROM ohdsi.sec_user WHERE login = 'admin'
);

-- ==========================================
-- 2. Create OMOP source if not exists
-- ==========================================
INSERT INTO ohdsi.source
(source_id, source_name, source_key, source_connection, source_dialect, username, "password",
 krb_auth_method, keytab_name, krb_keytab, krb_admin_server,
 deleted_date, created_by_id, created_date, modified_by_id, modified_date,
 is_cache_enabled, check_connection)
SELECT nextval('ohdsi.source_sequence'::regclass),
       'OMOP Postgres',
       'omop_local',
       'jdbc:postgresql://omop-db:5432/omop',
       'postgresql',
       'omop',
       'omop',
       'PASSWORD',
       '',
       '',
       '',
       NULL,
       su.id,
       CURRENT_DATE,
       su.id,
       CURRENT_DATE,
       FALSE,
       TRUE
FROM ohdsi.sec_user su
WHERE su.login = 'admin'
  AND NOT EXISTS (
    SELECT 1 FROM ohdsi.source WHERE source_key = 'omop_local'
);

-- ==========================================
-- 3. Create source_daimon entries
-- ==========================================
WITH src AS (
    SELECT source_id FROM ohdsi.source WHERE source_key = 'omop_local'
)
INSERT INTO ohdsi.source_daimon
(source_daimon_id, source_id, daimon_type, table_qualifier, priority)
SELECT nextval('ohdsi.source_daimon_sequence'::regclass),
       src.source_id,
       CASE dt.daimon_type
           WHEN 'CDM' THEN 0
           WHEN 'Vocabulary' THEN 1
           WHEN 'Results' THEN 2
           END AS daimon_type,
       CASE dt.daimon_type
           WHEN 'CDM' THEN 'public'
           WHEN 'Vocabulary' THEN 'public'
           WHEN 'Results' THEN 'results'
           END AS table_qualifier,
       0
FROM src
         CROSS JOIN (VALUES ('CDM'), ('Vocabulary'), ('Results')) AS dt(daimon_type)
WHERE NOT EXISTS (
    SELECT 1 FROM ohdsi.source_daimon sd
    WHERE sd.source_id = src.source_id
      AND sd.daimon_type =
          CASE dt.daimon_type
              WHEN 'CDM' THEN 0
              WHEN 'Vocabulary' THEN 1
              WHEN 'Results' THEN 2
              END
);
"""


def wait_for_db():
    while True:
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASS
            )
            cur = conn.cursor()
            cur.execute("SELECT 1 FROM ohdsi.sec_user LIMIT 1;")
            break
        except Exception:
            print("WebAPI tables not ready, waiting...")
            time.sleep(5)


def run_sql():
    conn = psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )

    conn.autocommit = True
    cur = conn.cursor()

    print("Running WebAPI initialization SQL...")
    cur.execute(SQL)

    cur.close()
    conn.close()

    print("Initialization complete")


if __name__ == "__main__":
    wait_for_db()
    run_sql()