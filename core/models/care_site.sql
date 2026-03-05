MODEL(
        name omop_db.CARE_SITE,
        kind FULL,
        columns(
                care_site_id INT NOT NULL,
                care_site_name VARCHAR(225),
                place_of_service_concept_id INT,
                location_id INT,
                care_site_source_value VARCHAR(50),
                place_of_service_source_value VARCHAR(50)
        )
);

SELECT l.location_id AS care_site_id,
       l.name        AS care_site_name,
       NULL          AS place_of_service_concept_id,
       l.location_id AS location_id,
       l.name        AS care_site_source_value,
       NULL          AS place_of_service_source_value
FROM openmrs.location AS l
WHERE l.retired = 0;
