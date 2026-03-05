MODEL(
        name omop_db.OBSERVATION,
        kind FULL,
        columns(
                observation_id INT NOT NULL,
                person_id INT NOT NULL,
                observation_concept_id INT NOT NULL,
                observation_date DATE NOT NULL,
                observation_datetime TIMESTAMP,
                observation_type_concept_id INT NOT NULL,
                value_as_number NUMERIC,
                value_as_string VARCHAR(60),
                value_as_concept_id INT,
                qualifier_concept_id INT,
                unit_concept_id INT,
                provider_id INT,
                visit_occurrence_id INT,
                visit_detail_id INT,
                observation_source_value VARCHAR(50),
                observation_source_concept_id INT,
                unit_source_value VARCHAR(50),
                qualifier_source_value VARCHAR(50),
                value_source_value VARCHAR(50),
                observation_event_id BIGINT,
                obs_event_field_concept_id INT
        )
);

SELECT o.obs_id                        AS observation_id,
       o.person_id                     AS person_id,
       concept_mapping.conceptId       AS observation_concept_id,
       DATE(o.obs_datetime)            AS observation_date,
       o.obs_datetime                  AS observation_datetime,
       32827                           AS observation_type_concept_id, -- EHR encounter record
       o.value_numeric                 AS value_as_number,
       LEFT(o.value_text, 60)          AS value_as_string,
       value_concept_mapping.conceptId AS value_as_concept_id,
       NULL                            AS qualifier_concept_id,
       NULL                            AS unit_concept_id,
       creator.person_id               AS provider_id,
       e.visit_id                      AS visit_occurrence_id,
       NULL                            AS visit_detail_id,
       ''                              AS observation_source_value,
       concept_mapping.conceptId       AS observation_source_concept_id,
       cn.units                        AS unit_source_value,
       ''                              AS qualifier_source_value,
       o.value_numeric                 AS value_source_value,
       NULL                            AS observation_event_id,
       NULL                            AS obs_event_field_concept_id
FROM openmrs.obs AS o
         INNER JOIN openmrs.encounter e ON o.encounter_id = e.encounter_id
         LEFT JOIN openmrs.concept_numeric cn ON o.concept_id = cn.concept_id
         LEFT JOIN raw.CONCEPT_MAPPING concept_mapping
                   ON o.concept_id = concept_mapping.sourceCode
         INNER JOIN openmrs.users creator ON o.creator = creator.user_id
         LEFT JOIN raw.CONCEPT_MAPPING value_concept_mapping
                   ON o.value_coded = value_concept_mapping.sourceCode
WHERE o.voided = 0
  AND concept_mapping.domainId = 'Observation';

