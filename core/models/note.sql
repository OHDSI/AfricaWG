MODEL(
        name omop_db.NOTE,
        kind FULL,
        columns(
                note_id INT NOT NULL,
                person_id INT NOT NULL,
                note_date DATE NOT NULL,
                note_datetime TIMESTAMP,
                note_type_concept_id INT NOT NULL,
                note_class_concept_id INT NOT NULL,
                note_title VARCHAR(250),
                note_text TEXT NOT NULL,
                encoding_concept_id INT NOT NULL,
                language_concept_id INT NOT NULL,
                provider_id INT,
                visit_occurrence_id INT,
                visit_detail_id INT,
                note_source_value VARCHAR(50),
                note_event_id BIGINT,
                note_event_field_concept_id INT
        )
);

SELECT cw_obs.omop_id       AS note_id,
       cw_person.omop_id    AS person_id,
       DATE(o.obs_datetime) AS note_date,
       o.obs_datetime       AS note_datetime,
       44814645             AS note_type_concept_id,  -- "Note"
       44814645             AS note_class_concept_id, -- "Note"
       ''                   AS note_title,
       o.value_text         AS note_text,
       4180186              AS encoding_concept_id,   -- UTF-8
       0                    AS language_concept_id,
       cw_provider.omop_id  AS provider_id,
       cw_visit.omop_id     AS visit_occurrence_id,
       NULL                 AS visit_detail_id,
       ''                   AS note_source_value,
       NULL                 AS note_event_id,
       NULL                 AS note_event_field_concept_id
FROM openmrs.obs o
         INNER JOIN raw.ID_CROSSWALK cw_obs
           ON o.obs_id = cw_obs.source_id
             AND cw_obs.source_table = 'obs'

         INNER JOIN raw.ID_CROSSWALK cw_person
           ON o.person_id = cw_person.source_id
             AND cw_person.source_table = 'person'

        LEFT JOIN raw.ID_CROSSWALK cw_provider
         ON o.creator = cw_provider.source_id
           AND cw_provider.source_table = 'users'

         INNER JOIN openmrs.encounter e ON o.encounter_id = e.encounter_id

         INNER JOIN raw.ID_CROSSWALK cw_visit
           ON e.visit_id = cw_visit.source_id
             AND cw_visit.source_table = 'visit'

         LEFT JOIN raw.CONCEPT_MAPPING concept_mapping
                   ON o.concept_id = concept_mapping.sourceCode
WHERE o.voided = 0
  AND o.value_text IS NOT NULL
  AND concept_mapping.conceptId = 45912632
  OR concept_mapping.domainId = 'Note';
