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

SELECT l.location_id               AS location_id,
       l.address1                  AS address_1,
       l.address2                  AS address_2,
       l.city_village              AS city,
       LEFT(l.state_province, 2)   AS state,
       LEFT(l.postal_code, 9)      AS zip,
       LEFT(l.county_district, 20) AS county,
       l.name                      AS location_source_value,
       NULL                        AS country_concept_id,
       l.country                   AS country_source_value,
       NULLIF(l.latitude, '')      AS latitude,
       NULLIF(l.longitude, '')     AS longitude
FROM openmrs.location AS l
WHERE l.retired = 0;
