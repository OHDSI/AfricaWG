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

SELECT u.user_id                                  AS provider_id,
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
       u.uuid                                     AS provider_source_value,
       NULL                                       AS specialty_source_value,
       NULL                                       AS specialty_source_concept_id,
       p.gender                                   AS gender_source_value,
       CASE
           WHEN p.gender = 'M' THEN 8507
           WHEN p.gender = 'F' THEN 8532
           ELSE 0
           END                                    AS gender_source_concept_id
FROM openmrs.users AS u
         INNER JOIN openmrs.person AS p ON u.person_id = p.person_id
         INNER JOIN openmrs.person_name AS pn ON u.person_id = pn.person_id
WHERE u.retired = 0;
