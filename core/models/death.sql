MODEL(
        name omop_db.DEATH,
        kind FULL,
        columns(
                person_id INT NOT NULL,
                death_date DATE NOT NULL,
                death_datetime TIMESTAMP,
                death_type_concept_id INT,
                cause_concept_id INT,
                cause_source_value VARCHAR(50),
                cause_source_concept_id INT
        )
);

SELECT p.person_id                     AS person_id,
       DATE(p.death_date)              AS death_date,
       p.death_date                    AS death_datetime,
       32817                           AS death_type_concept_id, -- EHR record
       concept_mapping.conceptId       AS cause_concept_id,
       ''                              AS cause_source_value,
       concept_mapping.conceptId       AS cause_source_concept_id
FROM openmrs.person AS p
         LEFT JOIN raw.CONCEPT_MAPPING concept_mapping
                   ON p.cause_of_death = concept_mapping.sourceCode
WHERE p.dead = 1
  AND p.death_date IS NOT NULL;