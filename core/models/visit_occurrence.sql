MODEL(
        name omop_db.VISIT_OCCURRENCE,
        kind FULL,
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

SELECT v.visit_id                                   AS visit_occurrence_id,
       v.patient_id                                 AS person_id,
       0                                            AS visit_concept_id,
       DATE(v.date_started)                         AS visit_start_date,
       v.date_started                               AS visit_start_datetime,
       COALESCE(DATE(v.date_stopped), CURRENT_DATE) AS visit_end_date,
       COALESCE(v.date_stopped, CURRENT_TIMESTAMP)  AS visit_end_datetime,
       v.visit_type_id                              AS visit_type_concept_id,
       creator.person_id                            AS provider_id,
       v.location_id                                AS care_site_id,
       ''                                           AS visit_source_value,
       0                                            AS visit_source_concept_id,
       0                                            AS admitted_from_concept_id,
       ''                                           AS admitted_from_source_value,
       0                                            AS discharged_to_concept_id,
       ''                                           AS discharged_to_source_value,
       NULL                                         AS preceding_visit_occurrence_id
FROM openmrs.visit AS v
         INNER JOIN openmrs.users AS creator ON v.creator = creator.user_id;
