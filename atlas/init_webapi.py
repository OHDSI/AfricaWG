import time
import psycopg2
from psycopg2.extras import execute_batch

DB_HOST = "omop-db"
DB_NAME = "omop"
DB_USER = "omop"
DB_PASS = "omop"

CREATE_TEMP_SCHEMA = """
CREATE SCHEMA IF NOT EXISTS temp;
ALTER SCHEMA temp OWNER TO omop;
GRANT ALL PRIVILEGES ON SCHEMA temp TO omop;
"""

SQL = """
-- ==========================================
-- 1. Create admin user if not exists
-- ==========================================
INSERT INTO webapi.sec_user (login, name)
SELECT 'admin', 'Admin User'
WHERE NOT EXISTS (
    SELECT 1 FROM webapi.sec_user WHERE login = 'admin'
);

-- ==========================================
-- 2. Create OMOP source if not exists
-- ==========================================
INSERT INTO webapi.source
(source_id, source_name, source_key, source_connection, source_dialect, username, "password",
 krb_auth_method, keytab_name, krb_keytab, krb_admin_server,
 deleted_date, created_by_id, created_date, modified_by_id, modified_date,
 is_cache_enabled, check_connection)
SELECT nextval('webapi.source_sequence'::regclass),
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
FROM webapi.sec_user su
WHERE su.login = 'admin'
  AND NOT EXISTS (
    SELECT 1 FROM webapi.source WHERE source_key = 'omop_local'
);

-- ==========================================
-- 3. Create source_daimon entries
-- ==========================================
WITH src AS (
    SELECT source_id FROM webapi.source WHERE source_key = 'omop_local'
)
INSERT INTO webapi.source_daimon
(source_daimon_id, source_id, daimon_type, table_qualifier, priority)
SELECT nextval('webapi.source_daimon_sequence'::regclass),
       src.source_id,
       CASE dt.daimon_type
           WHEN 'CDM' THEN 0
           WHEN 'Vocabulary' THEN 1
           WHEN 'Results' THEN 2
           WHEN 'CEM' THEN 3
           WHEN 'CEMResults' THEN 4
           WHEN 'Temp' THEN 5
           END AS daimon_type,
       CASE dt.daimon_type
           WHEN 'CDM' THEN 'public'
           WHEN 'Vocabulary' THEN 'public'
           WHEN 'Results' THEN 'webapi'
           WHEN 'CEM' THEN 'webapi'
           WHEN 'CEMResults' THEN 'webapi'
           WHEN 'Temp' THEN 'temp'
           END AS table_qualifier,
       0
FROM src
         CROSS JOIN (VALUES ('CDM'), ('Vocabulary'), ('Results'),('CEM'),('CEMResults'),('Temp')) AS dt(daimon_type)
WHERE NOT EXISTS (
    SELECT 1 FROM webapi.source_daimon sd
    WHERE sd.source_id = src.source_id
      AND sd.daimon_type =
          CASE dt.daimon_type
              WHEN 'CDM' THEN 0
              WHEN 'Vocabulary' THEN 1
              WHEN 'Results' THEN 2
              WHEN 'CEM' THEN 3
              WHEN 'CEMResults' THEN 4
              WHEN 'Temp' THEN 5
              END
);

-- Create the Characterization cc_results table
CREATE TABLE IF NOT EXISTS webapi.cc_results
(
    type VARCHAR(255) NOT NULL,
    fa_type VARCHAR(255) NOT NULL,
    cc_generation_id BIGINT NOT NULL,
    analysis_id INTEGER,
    analysis_name VARCHAR(1000),
    covariate_id BIGINT,
    covariate_name VARCHAR(1000),
    strata_id BIGINT,
    strata_name VARCHAR(1000),
    time_window VARCHAR(255),
    concept_id INTEGER NOT NULL,
    count_value BIGINT,
    avg_value DOUBLE PRECISION,
    stdev_value DOUBLE PRECISION,
    min_value DOUBLE PRECISION,
    p10_value DOUBLE PRECISION,
    p25_value DOUBLE PRECISION,
    median_value DOUBLE PRECISION,
    p75_value DOUBLE PRECISION,
    p90_value DOUBLE PRECISION,
    max_value DOUBLE PRECISION,
    cohort_definition_id BIGINT,
    aggregate_id INTEGER,
    aggregate_name VARCHAR(1000),
    missing_means_zero INTEGER
    );

-- Create the concept_hierarchy  table
DROP TABLE IF EXISTS webapi.concept_hierarchy;

CREATE TABLE webapi.concept_hierarchy AS
WITH achilles_stats AS (
    -- Get person counts from Achilles Analysis 400
    SELECT
        CAST(stratum_1 AS BIGINT) as concept_id,
        count_value as person_count
    FROM webapi.achilles_results
    WHERE analysis_id = 400
),
     denominator AS (
         -- Get total person count for percentage calculation (Analysis 1)
         SELECT CAST(count_value AS FLOAT) as total_p
         FROM webapi.achilles_results
         WHERE analysis_id = 1
    LIMIT 1
    )
SELECT
    snomed.concept_id,
    snomed.concept_name,
    'Condition' AS treemap,
    -- Hierarchical Levels for Drill-down
    COALESCE(soc.concept_name, 'NA') AS level1_concept_name,
    COALESCE(hlgt_to_soc.hlgt_concept_name, 'NA') AS level2_concept_name,
    COALESCE(hlt_to_hlgt.hlt_concept_name, 'NA') AS level3_concept_name,
    COALESCE(pt_to_hlt.pt_concept_name, 'NA') AS level4_concept_name,
    -- Full Breadcrumb Path
    CONCAT(
            COALESCE(soc.concept_name, 'NA'), '||',
            COALESCE(hlgt_to_soc.hlgt_concept_name, 'NA'), '||',
            COALESCE(hlt_to_hlgt.hlt_concept_name, 'NA'), '||',
            COALESCE(pt_to_hlt.pt_concept_name, 'NA'), '||',
            snomed.concept_name
    ) AS concept_path,
    'Condition' AS domain_id,
    -- Prevalence Statistics (Atlas expects these columns)
    COALESCE(stats.person_count, 0) AS person_count,
    ROUND(COALESCE(stats.person_count / NULLIF(denom.total_p, 0), 0)::numeric, 5) AS percent_persons
FROM (
         SELECT concept_id, concept_name
         FROM public.concept
         WHERE domain_id = 'Condition' AND standard_concept = 'S'
     ) snomed
         LEFT JOIN achilles_stats stats ON snomed.concept_id = stats.concept_id
         CROSS JOIN denominator denom

-- MedDRA Hierarchy Joins
         LEFT JOIN (
    SELECT ca1.descendant_concept_id AS snomed_concept_id, c2.concept_id AS pt_concept_id, c2.concept_name AS pt_concept_name
    FROM public.concept_ancestor ca1
             JOIN public.concept c2 ON ca1.ancestor_concept_id = c2.concept_id
    WHERE c2.vocabulary_id = 'MedDRA' AND c2.concept_class_id = 'PT'
) pt_to_hlt ON snomed.concept_id = pt_to_hlt.snomed_concept_id

         LEFT JOIN (
    SELECT ca1.descendant_concept_id AS pt_concept_id, c2.concept_id AS hlt_concept_id, c2.concept_name AS hlt_concept_name
    FROM public.concept_ancestor ca1
             JOIN public.concept c2 ON ca1.ancestor_concept_id = c2.concept_id
    WHERE c2.vocabulary_id = 'MedDRA' AND c2.concept_class_id = 'HLT'
) hlt_to_hlgt ON pt_to_hlt.pt_concept_id = hlt_to_hlgt.pt_concept_id

         LEFT JOIN (
    SELECT ca1.descendant_concept_id AS hlt_concept_id, c2.concept_id AS hlgt_concept_id, c2.concept_name AS hlgt_concept_name
    FROM public.concept_ancestor ca1
             JOIN public.concept c2 ON ca1.ancestor_concept_id = c2.concept_id
    WHERE c2.vocabulary_id = 'MedDRA' AND c2.concept_class_id = 'HLGT'
) hlgt_to_soc ON hlt_to_hlgt.hlt_concept_id = hlgt_to_soc.hlgt_concept_id

         LEFT JOIN (
    SELECT ca1.descendant_concept_id AS hlgt_concept_id, c2.concept_id AS soc_concept_id
    FROM public.concept_ancestor ca1
             JOIN public.concept c2 ON ca1.ancestor_concept_id = c2.concept_id
    WHERE c2.vocabulary_id = 'MedDRA' AND c2.concept_class_id = 'SOC'
) soc_id_map ON hlgt_to_soc.hlgt_concept_id = soc_id_map.hlgt_concept_id

         LEFT JOIN public.concept soc ON soc_id_map.soc_concept_id = soc.concept_id;

-- Indices for performance
CREATE INDEX idx_ch_treemap ON webapi.concept_hierarchy (treemap);
CREATE INDEX idx_ch_concept_id ON webapi.concept_hierarchy (concept_id);
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
            cur.execute("SELECT 1 FROM webapi.sec_user LIMIT 1;")
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
    cur.execute(CREATE_TEMP_SCHEMA)
    cur.execute(SQL)

    cur.close()
    conn.close()

    print("Initialization complete")


if __name__ == "__main__":
    wait_for_db()
    run_sql()