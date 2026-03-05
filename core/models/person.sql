MODEL(
        name omop_db.PERSON,
        kind FULL,
        columns(
                person_id INT NOT NULL,
                gender_concept_id INT NOT NULL,
                year_of_birth INT NOT NULL,
                month_of_birth INT,
                day_of_birth INT,
                birth_datetime DATETIME,
                race_concept_id INT NOT NULL,
                ethnicity_concept_id INT NOT NULL,
                location_id INT,
                provider_id INT,
                care_site_id INT,
                person_source_value VARCHAR(50),
                gender_source_value VARCHAR(50),
                gender_source_concept_id INT,
                race_source_value VARCHAR(50),
                race_source_concept_id INT,
                ethnicity_source_value VARCHAR(50),
                ethnicity_source_concept_id INT
        )
);

SELECT p.patient_id         AS person_id,
       CASE
           WHEN per.gender = 'M' THEN 8507 -- OMOP concept_id for Male
           WHEN per.gender = 'F' THEN 8532 -- OMOP concept_id for Female
           ELSE 0
           END              AS gender_concept_id,
       YEAR(per.birthdate)  AS year_of_birth,
       MONTH(per.birthdate) AS month_of_birth,
       DAY(per.birthdate)   AS day_of_birth,
       per.birthdate        AS birth_datetime,
       0                    AS race_concept_id,
       0                    AS ethnicity_concept_id,
       1                    AS location_id,
       creator.person_id    AS provider_id,
       1                    AS care_site_id,
       ''                   AS person_source_value,
       per.gender           AS gender_source_value,
       0                    AS gender_source_concept_id,
       ''                   AS race_source_value,
       0                    AS race_source_concept_id,
       ''                   AS ethnicity_source_value,
       0                    AS ethnicity_source_concept_id
FROM openmrs.patient AS p
         INNER JOIN openmrs.person AS per ON p.patient_id = per.person_id
         INNER JOIN openmrs.users AS creator ON p.creator = creator.user_id;
