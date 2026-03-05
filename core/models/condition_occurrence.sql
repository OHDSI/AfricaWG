MODEL(
        name omop_db.CONDITION_OCCURRENCE,
        kind FULL,
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

SELECT c.condition_id                      AS condition_occurrence_id,
       c.patient_id                        AS person_id,
       concept_mapping.conceptId           AS condition_concept_id,
       DATE(c.onset_date)                  AS condition_start_date,
       c.onset_date                        AS condition_start_datetime,
       DATE(c.end_date)                    AS condition_end_date,
       c.end_date                          AS condition_end_datetime,
       0                                   AS condition_type_concept_id,
       0                                   AS condition_status_concept_id,
       COALESCE(c.void_reason, '')         AS stop_reason,
       NULL                                AS provider_id,
       NULL                                AS visit_occurrence_id,
       NULL                                AS visit_detail_id,
       ''                                  AS condition_source_value,
       concept_mapping.conceptId           AS condition_source_concept_id,
       COALESCE(c.verification_status, '') AS condition_status_source_value
FROM openmrs.conditions AS c
         LEFT JOIN raw.CONCEPT_MAPPING concept_mapping
                    ON c.condition_coded = concept_mapping.sourceCode
WHERE c.voided = 0
  AND c.onset_date IS NOT NULL;
