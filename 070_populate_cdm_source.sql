SET session_replication_role = 'replica';
INSERT INTO public.cdm_source (
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
SELECT
    'OMRS',
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
WHERE NOT EXISTS (
    SELECT 1
    FROM public.cdm_source
    WHERE cdm_source_name = 'OMRS'
);
-- Re-enable constraints
SET session_replication_role = 'origin';
