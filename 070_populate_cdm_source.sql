-- remove any previously added database connection configuration data
truncate omop.cdm_source;

INSERT INTO omop.cdm_source (
    cdm_source_name,
    cdm_source_abbreviation,
    cdm_holder,
    source_description,
    source_documentation_reference,
    cdm_etl_reference,
    source_release_date,
    cdm_release_date,
    cdm_version,
    cdm_version_concept_id,
    vocabulary_version
)
VALUES (
           'OpenMRS OMOP CDM',
           'OMRS',
           'OpenMRS Community',
           'OMOP CDM instance generated from OpenMRS data.',
           'https://openmrs.org',
           'https://github.com/OHDSI/AfricaWG.git',
           CURRENT_DATE,
           CURRENT_DATE,
           '5.4',
           756265,
           'v5.0'
       );
