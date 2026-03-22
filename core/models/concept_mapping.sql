MODEL
(
  name raw.CONCEPT_MAPPING,
  kind FULL
);

WITH Usagi_Safe AS (
                 SELECT
                     sourceCode AS sourceCode,
                     sourceName AS source_name,
                     conceptId AS conceptId,
                     domainId AS domainId,
                     sourceFrequency::INT AS frequency, 'MANUAL_USAGI' AS mapping_source
                 FROM raw.CONCEPT_USAGI_MAPPING
                 WHERE 1 = 0

                 UNION ALL

                 SELECT
                   sourceCode,
                  sourceName,
                     conceptId,
                   domainId,
                sourceFrequency,
                 'MANUAL_USAGI'
                    FROM raw.CONCEPT_USAGI_MAPPING
                    WHERE conceptId IS NOT NULL
                      AND conceptId != 0
    )


SELECT *
FROM Usagi_Safe

UNION ALL

SELECT
    source_concept_id AS sourceCode,
    source_concept_name AS sourceName,
    target_concept_id AS conceptId,
    source_domain AS domainId,
    frequency AS frequency,
    match_status AS mapping_source
FROM raw.CONCEPT_AUTO_MAPPING
WHERE
    match_status != 'USAGI_REQUIRED'
  AND match_status != 'FAILED_ATHENA'
  AND source_concept_id NOT IN (SELECT sourceCode FROM Usagi_Safe);