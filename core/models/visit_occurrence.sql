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

SELECT cw_visit.omop_id                             AS visit_occurrence_id,
       cw_person.omop_id                            AS person_id,
       CASE
           WHEN v.visit_type_id = 1 THEN 9201  -- Standard: Inpatient Visit
           ELSE 9202                          -- Standard: Outpatient Visit
       END                                          AS visit_concept_id,
       DATE(v.date_started)                         AS visit_start_date,
       v.date_started                               AS visit_start_datetime,
       COALESCE(DATE(v.date_stopped), DATE(v.date_started)) AS visit_end_date,
       COALESCE(v.date_stopped, v.date_started)     AS visit_end_datetime,
       32817                                        AS visit_type_concept_id,
       cw_provider.omop_id                          AS provider_id,
       cw_location.omop_id                          AS care_site_id,
       ''                                           AS visit_source_value,
       0                                            AS visit_source_concept_id,
       0                                            AS admitted_from_concept_id,
       ''                                           AS admitted_from_source_value,
       0                                            AS discharged_to_concept_id,
       ''                                           AS discharged_to_source_value,
       NULL                                         AS preceding_visit_occurrence_id
FROM openmrs.visit AS v
        INNER JOIN raw.ID_CROSSWALK cw_visit
         ON v.visit_id = cw_visit.source_id
           AND cw_visit.source_table = 'visit'

        INNER JOIN raw.ID_CROSSWALK cw_person
           ON v.patient_id = cw_person.source_id
             AND cw_person.source_table = 'person'

        LEFT JOIN raw.ID_CROSSWALK cw_provider
         ON v.creator = cw_provider.source_id
           AND cw_provider.source_table = 'users'

        LEFT JOIN raw.ID_CROSSWALK cw_location
        ON v.location_id = cw_location.source_id
                AND cw_location.source_table = 'location'
        WHERE v.voided = 0;
