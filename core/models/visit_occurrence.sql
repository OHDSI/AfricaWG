MODEL(
        name omop_db.VISIT_OCCURRENCE,
        kind INCREMENTAL_BY_TIME_RANGE (
          time_column visit_start_date,
          batch_size 20
        ),
        grain visit_occurrence_id,
        columns(
                visit_occurrence_id INT NOT NULL,
                person_id INT NOT NULL,
                visit_concept_id INT NOT NULL,
                visit_start_date DATE NOT NULL,
                visit_start_datetime TIMESTAMP,
                visit_end_date DATE NOT NULL,
                visit_end_datetime TIMESTAMP,
                visit_type_concept_id INT NOT NULL,
                provider_id INT,
                care_site_id INT,
                visit_source_value VARCHAR(50),
                visit_source_concept_id INT,
                admitted_from_concept_id INT,
                admitted_from_source_value VARCHAR(50),
                discharged_to_concept_id INT,
                discharged_to_source_value VARCHAR(50),
                preceding_visit_occurrence_id INT
        )
);

WITH provider_per_visit AS (
       SELECT e.visit_id,
              MIN(ep.provider_id) AS provider_id
       FROM openmrs.encounter e
         LEFT JOIN openmrs.encounter_provider ep
                   ON e.encounter_id = ep.encounter_id
       GROUP BY e.visit_id
)
SELECT v.visit_id                             AS visit_occurrence_id,
       v.patient_id                            AS person_id,
       CASE
           WHEN v.visit_type_id = 1 THEN 9201  -- Standard: Inpatient Visit
           ELSE 9202                          -- Standard: Outpatient Visit
       END                                          AS visit_concept_id,
       DATE(v.date_started)                         AS visit_start_date,
       v.date_started                               AS visit_start_datetime,
       COALESCE(DATE(v.date_stopped), DATE(v.date_started)) AS visit_end_date,
       COALESCE(v.date_stopped, v.date_started)     AS visit_end_datetime,
       32817                                        AS visit_type_concept_id,
       ppv.provider_id                          AS provider_id,
       v.location_id                          AS care_site_id,
       ''                                           AS visit_source_value,
       0                                            AS visit_source_concept_id,
       0                                            AS admitted_from_concept_id,
       ''                                           AS admitted_from_source_value,
       0                                            AS discharged_to_concept_id,
       ''                                           AS discharged_to_source_value,
       NULL                                         AS preceding_visit_occurrence_id
FROM openmrs.visit AS v
    LEFT JOIN provider_per_visit ppv  ON v.visit_id = ppv.visit_id
        WHERE v.voided = 0
          AND v.date_started BETWEEN @start_ds AND @end_ds;
