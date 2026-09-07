SELECT
o.concept_id AS question_concept_id,
q_name.name  AS question_name,
o.value_coded AS answer_concept_id,
a_name.name  AS answer_name,
COUNT(*)     AS occurrence_count
FROM obs o
JOIN concept_name q_name
ON o.concept_id = q_name.concept_id
AND q_name.locale = 'en'
AND q_name.concept_name_type = 'FULLY_SPECIFIED'
AND q_name.voided = 0
JOIN concept_name a_name
ON o.value_coded = a_name.concept_id
AND a_name.locale = 'en'
AND a_name.concept_name_type = 'FULLY_SPECIFIED'
AND a_name.voided = 0
WHERE o.voided = 0
AND o.value_coded IN (3480)
GROUP BY o.concept_id, q_name.name, o.value_coded, a_name.name
ORDER BY occurrence_count DESC;