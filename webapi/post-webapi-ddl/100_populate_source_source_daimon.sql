-- Insert source if source_key 'OMRS' doesn't already exist
INSERT INTO webapi.source
(source_id, source_name, source_key, source_connection, source_dialect, username, password, krb_auth_method)
VALUES (
           nextval('webapi.source_sequence'),
           'OMRS',
           'OMRS',
           'jdbc:postgresql://omop-db:5432/postgres?user=postgres&password=postgres_pass',
           'postgresql',
           NULL,
           NULL,
           'PASSWORD'
       )
    ON CONFLICT (source_key) DO UPDATE SET
    source_connection = EXCLUDED.source_connection;

-- Insert source daimons for OMRS (0 = CDM, 1 = Vocabulary, 2 = Results)
INSERT INTO webapi.source_daimon (source_daimon_id, source_id, daimon_type, table_qualifier, priority)
SELECT
    nextval('webapi.source_daimon_sequence'),
    s.source_id,
    d.daimon_type,
    d.table_qualifier,
    d.priority
FROM webapi.source s
         CROSS JOIN (
    VALUES
        (0, 'public', 0),    -- CDM Daimon
        (1, 'public', 10),   -- Vocabulary Daimon
        (2, 'cdm_results', 5) -- Results Daimon
) AS d(daimon_type, table_qualifier, priority)
WHERE s.source_key = 'OMRS'
    ON CONFLICT (source_id, daimon_type) DO NOTHING;