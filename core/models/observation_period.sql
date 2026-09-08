MODEL(
        name omop_db.OBSERVATION_PERIOD,
        kind FULL,
        columns(
                observation_period_id INT NOT NULL,
                person_id INT NOT NULL,
                observation_period_start_date DATE NOT NULL,
                observation_period_end_date DATE NOT NULL,
                period_type_concept_id INT NOT NULL
        )
);

WITH patient_bounds AS (
    SELECT
        v.patient_id,
        MIN(CAST(v.date_started AS DATETIME)) as min_start,
        GREATEST(MAX(CAST(v.date_stopped AS DATETIME)), MAX(CAST(e.encounter_datetime AS DATETIME))) as max_end
    FROM openmrs.visit v
             LEFT JOIN openmrs.encounter e ON v.visit_id = e.visit_id
    WHERE v.date_started IS NOT NULL
    GROUP BY v.patient_id
)
SELECT
    ROW_NUMBER() OVER (ORDER BY min_start) AS observation_period_id,
    patient_id AS person_id,
    CAST(min_start AS DATE) AS observation_period_start_date,
    CAST(CASE WHEN max_end < min_start THEN min_start ELSE max_end END AS DATE) AS observation_period_end_date,
    44814724 AS period_type_concept_id
FROM patient_bounds
WHERE min_start IS NOT NULL;