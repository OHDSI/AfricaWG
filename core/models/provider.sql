MODEL(
        name omop_db.PROVIDER,
        kind FULL,
        columns(
                provider_id INT NOT NULL,
                provider_name VARCHAR(255),
                npi VARCHAR(20),
                dea VARCHAR(20),
                specialty_concept_id INT,
                care_site_id INT,
                gender_concept_id INT,
                provider_source_value VARCHAR(50),
                specialty_source_value VARCHAR(50),
                specialty_source_concept_id INT,
                gender_source_value VARCHAR(50),
                gender_source_concept_id INT
        )
);

SELECT provider_id                       AS provider_id,
       CONCAT(pn.given_name, ' ', pn.family_name) AS provider_name,
       NULL                                       AS npi,
       NULL                                       AS dea,
       NULL                                       AS specialty_concept_id,
       NULL                                       AS care_site_id,
       CASE
           WHEN p.gender = 'M' THEN 8507 -- OMOP concept_id for Male
           WHEN p.gender = 'F' THEN 8532 -- OMOP concept_id for Female
           ELSE 0
           END                                    AS gender_concept_id,
       pv.uuid                                     AS provider_source_value,
       cn.name                                       AS specialty_source_value,
       c.concept_id                                       AS specialty_source_concept_id,
       p.gender                                   AS gender_source_value,
       CASE
           WHEN p.gender = 'M' THEN 8507
           WHEN p.gender = 'F' THEN 8532
           ELSE 0
           END                                    AS gender_source_concept_id
FROM openmrs.provider pv
         LEFT JOIN openmrs.person  p ON pv.person_id = p.person_id
         LEFT JOIN openmrs.person_name  pn ON p.person_id = pn.person_id
         LEFT JOIN  openmrs.concept c ON  pv.speciality_id = c.concept_id
         LEFT JOIN  openmrs.concept_name cn ON  c.concept_id = cn.concept_id
                  AND cn.locale = 'en'  --- to be added to the concept_mapping (To--Do)
                  AND cn.concept_name_type = 'FULLY_SPECIFIED'

WHERE pv.retired = 0;
