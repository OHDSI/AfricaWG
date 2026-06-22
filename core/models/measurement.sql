MODEL
(
        name omop_db.MEASUREMENT,
        kind INCREMENTAL_BY_TIME_RANGE (
           time_column measurement_date,
           batch_size 30,
           batch_concurrency 1
        ),
        grain measurement_id,
        columns(
                measurement_id INT NOT NULL,
                person_id INT NOT NULL,
                measurement_concept_id INT NOT NULL,
                measurement_date DATE NOT NULL,
                measurement_datetime TIMESTAMP,
                measurement_time VARCHAR(10),
                measurement_type_concept_id INT NOT NULL,
                operator_concept_id INT,
                value_as_number NUMERIC,
                value_as_concept_id INT,
                unit_concept_id INT,
                range_low NUMERIC,
                range_high NUMERIC,
                provider_id INT,
                visit_occurrence_id INT,
                visit_detail_id INT,
                measurement_source_value VARCHAR(50),
                measurement_source_concept_id INT,
                unit_source_value VARCHAR(50),
                unit_source_concept_id INT,
                value_source_value VARCHAR(50),
                measurement_event_id BIGINT,
                meas_event_field_concept_id INT
        )
);

WITH filtered_obs AS (
   SELECT
             o.obs_id,
             o.person_id,
             o.concept_id,
             o.obs_datetime,
             o.value_numeric,
             o.value_coded,
             o.encounter_id
FROM openmrs.obs AS o
      WHERE o.voided = 0
AND o.obs_datetime BETWEEN @start_ds AND @end_ds
)

SELECT
       fo.obs_id                 AS measurement_id,
       fo.person_id              AS person_id,
       concept_mapping.conceptId AS measurement_concept_id,
       DATE (fo.obs_datetime) AS measurement_date,
       fo.obs_datetime AS measurement_datetime,
       DATE_FORMAT(fo.obs_datetime, '%H:%i:%s') AS measurement_time,
       44818701 AS measurement_type_concept_id,
       NULL AS operator_concept_id,
       fo.value_numeric AS value_as_number,
       value_concept_mapping.conceptId AS value_as_concept_id,
       NULL AS unit_concept_id,
       cn.low_normal AS range_low,
       cn.hi_normal AS range_high,
       ep.provider_id AS provider_id,
       e.visit_id AS visit_occurrence_id,
       NULL AS visit_detail_id,
       '' AS measurement_source_value,
       concept_mapping.conceptId AS measurement_source_concept_id,
       cn.units AS unit_source_value,
       NULL AS unit_source_concept_id,
       CAST (fo.value_numeric AS CHAR (50)) AS value_source_value,
       NULL AS measurement_event_id,
       NULL AS meas_event_field_concept_id

FROM filtered_obs fo
    INNER JOIN openmrs.concept c
ON fo.concept_id = c.concept_id
    INNER JOIN openmrs.concept_class cc
        ON c.class_id = cc.concept_class_id
         AND cc.name IN ('Test', 'Finding', 'Symptom/Finding', 'Aggregate Measurement', 'LabSet')

    INNER JOIN raw.CONCEPT_MAPPING concept_mapping
          ON fo.concept_id = concept_mapping.sourceCode
          AND concept_mapping.domainId = 'Measurement'
          AND concept_mapping.conceptId IS NOT NULL
          AND concept_mapping.conceptId <> ''

    LEFT JOIN openmrs.encounter e ON fo.encounter_id = e.encounter_id
    LEFT JOIN openmrs.encounter_provider ep ON e.encounter_id = ep.encounter_id
    LEFT JOIN openmrs.concept_numeric cn ON fo.concept_id = cn.concept_id

    LEFT JOIN raw.CONCEPT_MAPPING value_concept_mapping
         ON fo.value_coded IS NOT NULL
           AND fo.value_coded = value_concept_mapping.sourceCode



