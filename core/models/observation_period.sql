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


WITH patient_boundaries AS (
    SELECT
        v.patient_id AS person_id,
        -- Earliest known activity
        MIN(v.date_started) AS min_start,

        -- Latest known activity comparing visits and encounters
        MAX(v.date_started) AS max_visit_start,
        MAX(v.date_stopped) AS max_visit_stop,
        MAX(e.encounter_datetime) AS max_encounter
    FROM openmrs.visit v
             LEFT JOIN openmrs.encounter e
                       ON v.visit_id = e.visit_id
    WHERE v.voided = 0
    GROUP BY v.patient_id
)

SELECT
    person_id + 15000000             AS observation_period_id,
    person_id                        AS person_id,
    DATE(min_start)                  AS observation_period_start_date,

    -- find the absolute latest date using GREATEST on the pre-aggregated results
    DATE(GREATEST(
    COALESCE(max_visit_start, '1900-01-01'),
    COALESCE(max_visit_stop, '1900-01-01'),
    COALESCE(max_encounter, '1900-01-01')
    ))                               AS observation_period_end_date,
    44814724                         AS period_type_concept_id 
FROM patient_boundaries;
