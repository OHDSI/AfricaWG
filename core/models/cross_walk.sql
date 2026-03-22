MODEL (
  name raw.ID_CROSSWALK,
  kind FULL
);

SELECT 'location' AS source_table, location_id AS source_id,
       ROW_NUMBER() OVER (ORDER BY location_id) AS omop_id
FROM openmrs.location

UNION ALL

SELECT 'person' AS source_table, person_id AS source_id,
       ROW_NUMBER() OVER (ORDER BY person_id) + 1000000 AS omop_id
FROM openmrs.person

UNION ALL

SELECT 'conditions' AS source_table, condition_id AS source_id,
       ROW_NUMBER() OVER (ORDER BY condition_id) + 2000000 AS omop_id
FROM openmrs.conditions

UNION ALL

SELECT 'visit' AS source_table, visit_id AS source_id,
       ROW_NUMBER() OVER (ORDER BY visit_id) + 3000000 AS omop_id
FROM openmrs.visit

UNION ALL

SELECT 'obs' AS source_table, obs_id AS source_id,
       ROW_NUMBER() OVER (ORDER BY obs_id) + 4000000 AS omop_id
FROM openmrs.obs

UNION ALL

SELECT 'users' AS source_table, user_id AS source_id,
       ROW_NUMBER() OVER (ORDER BY user_id) + 14000000 AS omop_id
FROM openmrs.users;