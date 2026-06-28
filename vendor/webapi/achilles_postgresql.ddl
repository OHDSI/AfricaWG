/*******************************************************************/
/***** PHASE 1: Build-Time Schema Structure Only              *****/
/*******************************************************************/
DROP TABLE IF EXISTS cdm_results.achilles_result_concept_count;
DROP TABLE IF EXISTS cdm_results.achilles_performance;

-- Create the performance metadata table to prevent Achilles/Ares export crashes
CREATE TABLE cdm_results.achilles_performance
(
    analysis_id       int,
    analysis_name     varchar(255),
    elapsed_seconds   numeric,
    start_time        timestamp,
    end_time          timestamp,
    status            varchar(50)
);

CREATE TABLE cdm_results.achilles_result_concept_count
(
    concept_id                int NOT NULL,
    record_count              bigint,
    descendant_record_count   bigint,
    person_count              bigint,
    descendant_person_count   bigint,
    CONSTRAINT pk_achilles_rc_concept PRIMARY KEY (concept_id)
);

CREATE INDEX IF NOT EXISTS idx_achilles_rc_desc_cnt
    ON cdm_results.achilles_result_concept_count (descendant_record_count);


/*******************************************************************/
/***** PHASE 2: Trigger Function (Runs dynamically at runtime) *****/
/*******************************************************************/
CREATE OR REPLACE FUNCTION cdm_results.auto_populate_concept_counts()
RETURNS TRIGGER AS $$
BEGIN
    -- We only want to run this heavy calculation ONCE when Achilles finishes.
    -- Achilles inserts data using an analysis ID of 0 for its metadata row.
    -- If this is NOT the end-of-run metadata marker, skip execution to save resources.
    IF NEW.analysis_id <> 0 THEN
        RETURN NEW;
END IF;

    RAISE NOTICE 'Achilles execution completion detected. Automatically computing concept counts...';

DROP TABLE IF EXISTS tmp_counts;
CREATE TEMP TABLE tmp_counts AS
        WITH counts AS (
          SELECT stratum_1 AS concept_id, MAX (count_value) AS agg_count_value
          FROM cdm_results.achilles_results
          WHERE analysis_id IN (2, 4, 5, 201, 225, 301, 325, 401, 425, 501, 505, 525, 601, 625, 701, 725, 801, 825,
            826, 827, 901, 1001, 1201, 1203, 1425, 1801, 1825, 1826, 1827, 2101, 2125, 2301)
          GROUP BY stratum_1
          UNION ALL
          SELECT stratum_2 AS concept_id, SUM (count_value) AS agg_count_value
          FROM cdm_results.achilles_results
          WHERE analysis_id IN (405, 605, 705, 805, 807, 1805, 1807, 2105)
          GROUP BY stratum_2
        )
SELECT concept_id, agg_count_value FROM counts;

ANALYZE tmp_counts;

DROP TABLE IF EXISTS tmp_counts_person;
CREATE TEMP TABLE tmp_counts_person AS
        WITH counts_person AS (
          SELECT stratum_1 AS concept_id, MAX (count_value) AS agg_count_value
          FROM cdm_results.achilles_results
          WHERE analysis_id IN (200, 240, 400, 440, 540, 600, 640, 700, 740, 800, 840, 900, 1000, 1300, 1340, 1800, 1840, 2100, 2140, 2200)
          GROUP BY stratum_1
        )
SELECT concept_id, agg_count_value FROM counts_person;

ANALYZE tmp_counts_person;

DROP TABLE IF EXISTS tmp_concepts;
CREATE TEMP TABLE tmp_concepts AS
        WITH concepts AS (
          SELECT concept_id as ancestor_id, coalesce(cast(ca.descendant_concept_id as varchar(50)), concept_id) as descendant_id
          FROM (
            SELECT concept_id FROM tmp_counts
            UNION
            SELECT DISTINCT cast(ancestor_concept_id as varchar(50)) concept_id
            FROM tmp_counts c
            JOIN omop.concept_ancestor ca ON cast(ca.descendant_concept_id as varchar(50)) = c.concept_id
          ) c
          LEFT JOIN omop.concept_ancestor ca ON c.concept_id = cast(ca.ancestor_concept_id as varchar(50))
        )
SELECT ancestor_id, descendant_id FROM concepts;

ANALYZE tmp_concepts;

    -- Clear out old setup and sync fresh calculations
TRUNCATE TABLE cdm_results.achilles_result_concept_count;

INSERT INTO cdm_results.achilles_result_concept_count (concept_id, record_count, descendant_record_count, person_count, descendant_person_count)
SELECT DISTINCT
    cast(concepts.ancestor_id as int) AS concept_id,
    coalesce(max(c1.agg_count_value), 0) AS record_count,
    coalesce(sum(c2.agg_count_value), 0) AS descendant_record_count,
    coalesce(max(c3.agg_count_value), 0) AS person_count,
    coalesce(sum(c4.agg_count_value), 0) AS descendant_person_count
FROM tmp_concepts concepts
         LEFT JOIN tmp_counts c1 ON concepts.ancestor_id = c1.concept_id
         LEFT JOIN tmp_counts c2 ON concepts.descendant_id = c2.concept_id
         LEFT JOIN tmp_counts_person c3 ON concepts.ancestor_id = c3.concept_id
         LEFT JOIN tmp_counts_person c4 ON concepts.descendant_id = c4.concept_id
GROUP BY concepts.ancestor_id;

DROP TABLE IF EXISTS tmp_counts;
DROP TABLE IF EXISTS tmp_counts_person;
DROP TABLE IF EXISTS tmp_concepts;

RAISE NOTICE 'Concept counts populated successfully!';
RETURN NEW;
END;
$$ LANGUAGE plpgsql;


/*******************************************************************/
/***** PHASE 3: Bind Trigger to Achilles Table                     *****/
/***** Note: Since achilles_results might not exist yet during    *****/
/***** initdb if it's created by R later, we use a block statement. *****/
/*******************************************************************/
DO $$
BEGIN
    -- Only attach trigger if the table has been deployed by your setup scripts
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'cdm_results' AND table_name = 'achilles_results') THEN
DROP TRIGGER IF EXISTS trg_achilles_completion ON cdm_results.achilles_results;

CREATE TRIGGER trg_achilles_completion
    AFTER INSERT ON cdm_results.achilles_results
    FOR EACH ROW
    EXECUTE FUNCTION cdm_results.auto_populate_concept_counts();
END IF;
END $$;