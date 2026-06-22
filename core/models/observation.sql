MODEL(
        name omop_db.OBSERVATION,
        kind INCREMENTAL_BY_TIME_RANGE (
          time_column observation_date,
          batch_size 30,
          batch_concurrency 1
        ),
         grain observation_id,
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


WITH  filtered_obs AS (
    SELECT
        o.obs_id, o.person_id, o.concept_id, o.obs_datetime,
        o.value_numeric, o.value_text, o.value_coded, o.encounter_id
    FROM openmrs.obs AS o
    WHERE o.voided = 0
      AND o.obs_datetime BETWEEN @start_ds AND @end_ds
)
SELECT
    fo.obs_id                       AS observation_id,
    fo.person_id                    AS person_id,
    concept_mapping.conceptId       AS observation_concept_id,
    DATE(fo.obs_datetime)           AS observation_date,
    fo.obs_datetime                 AS observation_datetime,
    32827                           AS observation_type_concept_id, -- EHR encounter record
    fo.value_numeric                AS value_as_number,
    LEFT(fo.value_text, 60)         AS value_as_string,
    value_concept_mapping.conceptId AS value_as_concept_id,
    NULL                            AS qualifier_concept_id,
    NULL                            AS unit_concept_id,
    ep.provider_id                  AS provider_id,
    e.visit_id                      AS visit_occurrence_id,
    NULL                            AS visit_detail_id,
    ''                              AS observation_source_value,
    concept_mapping.conceptId       AS observation_source_concept_id,
    cn.units                        AS unit_source_value,
    ''                              AS qualifier_source_value,
    fo.value_numeric                AS value_source_value,
    NULL                            AS observation_event_id,
    NULL                            AS obs_event_field_concept_id
FROM filtered_obs fo

    INNER JOIN raw.CONCEPT_MAPPING concept_mapping
ON fo.concept_id = concept_mapping.sourceCode
    AND concept_mapping.domainId = 'Observation'
    AND concept_mapping.conceptId IS NOT NULL
    AND concept_mapping.conceptId <> ''

    LEFT JOIN openmrs.encounter e
    ON fo.encounter_id = e.encounter_id
    LEFT JOIN (
        SELECT encounter_id, MAX(provider_id) AS provider_id
         FROM openmrs.encounter_provider
         GROUP BY encounter_id
    ) ep ON e.encounter_id = ep.encounter_id
    LEFT JOIN openmrs.concept_numeric cn
    ON fo.concept_id = cn.concept_id

    LEFT JOIN raw.CONCEPT_MAPPING value_concept_mapping
       ON fo.value_coded IS NOT NULL
        AND fo.value_coded = value_concept_mapping.sourceCode
