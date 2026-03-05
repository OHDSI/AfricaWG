MODEL(
        name omop_db.OBSERVATION_PERIOD,
        kind FULL,
        columns(
                observation_period_id INT NOT NULL,
                person_id INT NOT NULL,
                observation_period_start_date DATE NOT NULL,
                observation_period_end_date DATE NOT NULL,
                period_type_concept_id INT NOT NULL
        )
);

SELECT ROW_NUMBER() OVER (ORDER BY MIN(v.date_started))               AS observation_period_id,
       v.patient_id                                                   AS person_id,
       DATE(MIN(v.date_started))                                      AS observation_period_start_date,
       DATE(GREATEST(MAX(v.date_stopped), MAX(e.encounter_datetime))) AS observation_period_end_date,
       44814724                                                       AS period_type_concept_id -- EHR recordd
FROM openmrs.visit v
         LEFT JOIN openmrs.encounter e ON v.visit_id = e.visit_id
WHERE v.date_started IS NOT NULL
GROUP BY v.patient_id;
