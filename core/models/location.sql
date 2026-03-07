MODEL(
        name omop_db.LOCATION,
        kind FULL,
        columns(
                location_id INT NOT NULL,
                address_1 VARCHAR(50),
                address_2 VARCHAR(50),
                city VARCHAR(50),
                state VARCHAR(2),
                zip VARCHAR(9),
                county VARCHAR(20),
                location_source_value VARCHAR(50),
                country_concept_id INT,
                country_source_value VARCHAR(80),
                latitude NUMERIC,
                longitude NUMERIC
        )
);

SELECT l.location_id,
       l.name           AS location_source_value,
       l.address1       AS address_1,
       l.address2       AS address_2,
       l.city_village   AS city,
       l.state_province AS state,
       l.postal_code    AS zip,
       l.country        AS country_source_value,
       l.latitude,
       l.longitude,
       NULL             AS county,
       0                AS country_concept_id
FROM openmrs.location AS l;;
