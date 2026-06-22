MODEL(
        name omop_db.CONDITION_OCCURRENCE,
        kind INCREMENTAL_BY_TIME_RANGE (
          time_column condition_start_date,
          batch_size 20,
          batch_concurrency 1
        ),
        grain condition_occurrence_id,
        columns(
                condition_occurrence_id INT NOT NULL,
                person_id INT NOT NULL,
                condition_concept_id INT NOT NULL,
                condition_start_date DATE NOT NULL,
                condition_start_datetime TIMESTAMP,
                condition_end_date DATE,
                condition_end_datetime TIMESTAMP,
                condition_type_concept_id INT NOT NULL,
                condition_status_concept_id INT,
                stop_reason VARCHAR(20),
                provider_id INT,
                visit_occurrence_id INT,
                visit_detail_id INT,
                condition_source_value VARCHAR(50),
                condition_source_concept_id INT,
                condition_status_source_value VARCHAR(50)
        )
);

SELECT
       c.condition_id                AS condition_occurrence_id,
       c.patient_id                       AS person_id,
       concept_mapping.conceptId           AS condition_concept_id,
       DATE(COALESCE(c.onset_date, c.date_created)) AS condition_start_date,
       COALESCE(c.onset_date, c.date_created)       AS condition_start_datetime,
       DATE(c.end_date)                    AS condition_end_date,
       c.end_date                          AS condition_end_datetime,
       0                                   AS condition_type_concept_id,
       0                                   AS condition_status_concept_id,
       COALESCE(c.void_reason, '')         AS stop_reason,
       ep.provider_id                 AS provider_id,
       e.visit_id                                AS visit_occurrence_id,
       NULL                                AS visit_detail_id,
       ''                                  AS condition_source_value,
       concept_mapping.conceptId           AS condition_source_concept_id,
--        To..Do
--     this should be the source concept source value ( NO STANDARD CONCEPT)
--     concept_mapping.conceptId           AS condition_source_concept_id,
       COALESCE(c.verification_status, '') AS condition_status_source_value
FROM openmrs.conditions AS c
         LEFT JOIN openmrs.encounter e ON c.encounter_id = e.encounter_id
         LEFT JOIN openmrs.encounter_provider ep ON e.encounter_id = ep.encounter_id
         LEFT JOIN raw.CONCEPT_MAPPING concept_mapping
                    ON c.condition_coded = concept_mapping.sourceCode
WHERE c.voided = 0
  AND concept_mapping.conceptId  IS NOT NULL
  AND (
    (c.onset_date BETWEEN @start_ds AND @end_ds)
   OR
    (c.onset_date IS NULL AND c.date_created BETWEEN @start_ds AND @end_ds)
    )
GROUP BY c.condition_id;
