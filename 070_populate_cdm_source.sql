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
    'OMOP Bridge',
    'OMOP-BRIDGE',
    'OMOP Bridge',
    'Healthcare data transformed into OMOP CDM using OMOP-Bridge ETL',
    'https://github.com/OHDSI/CommonDataModel',
    'OMOP-Bridge ETL pipeline',
    CURRENT_DATE,
    CURRENT_DATE,
    '5.4',
    756265,
    'Athena vocabulary'
WHERE NOT EXISTS (
    SELECT 1
    FROM public.cdm_source
    WHERE cdm_source_name = 'OMOP Bridge'
);
-- Re-enable constraints
SET session_replication_role = 'origin';