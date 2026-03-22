MODEL
(
  name raw.CONCEPT_MAPPING,
  kind FULL
);

WITH Usagi_Safe AS (
                 SELECT
                     sourceCode::TEXT AS sourceCode,
                     sourceName AS source_name,
                     conceptId::INT AS conceptId,
                     domainId AS domainId,
                     sourceFrequency::INT AS frequency, 'MANUAL_USAGI' AS mapping_source
                 FROM raw.CONCEPT_USAGI_MAPPING
                 WHERE 1 = 0

                 UNION ALL

                 SELECT
                   sourceCode::TEXT,
                  sourceName,
                     conceptId::INT,
                   domainId,
                sourceFrequency::INT,
                 'MANUAL_USAGI'
                    FROM raw.CONCEPT_USAGI_MAPPING
                    WHERE conceptId IS NOT NULL
                      AND conceptId != 0
    )


SELECT *
FROM Usagi_Safe

UNION ALL

SELECT
    source_concept_id::TEXT AS sourceCode,
    source_concept_name AS sourceName,
    target_concept_id::INT AS conceptId,
    target_domain AS domainId,
    frequency::INT AS frequency,
    match_status AS mapping_source
FROM raw.CONCEPT_AUTO_MAPPING
WHERE
    match_status != 'USAGI_REQUIRED'
  AND source_concept_id::TEXT
   NOT IN (SELECT sourceCode FROM Usagi_Safe);