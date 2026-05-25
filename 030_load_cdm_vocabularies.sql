\copy omop.domain FROM '/docker-entrypoint-initdb.d/DOMAIN.csv' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', QUOTE E'\b');

\copy omop.concept_class FROM '/docker-entrypoint-initdb.d/CONCEPT_CLASS.csv' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', QUOTE E'\b');

\copy omop.vocabulary FROM '/docker-entrypoint-initdb.d/VOCABULARY.csv' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', QUOTE E'\b');

\copy omop.relationship FROM '/docker-entrypoint-initdb.d/RELATIONSHIP.csv' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', QUOTE E'\b');

\copy omop.concept FROM '/docker-entrypoint-initdb.d/CONCEPT.csv' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', QUOTE E'\b');

\copy omop.concept_relationship FROM '/docker-entrypoint-initdb.d/CONCEPT_RELATIONSHIP.csv' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', QUOTE E'\b');

\copy omop.concept_ancestor FROM '/docker-entrypoint-initdb.d/CONCEPT_ANCESTOR.csv' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', QUOTE E'\b');

\copy omop.concept_synonym FROM '/docker-entrypoint-initdb.d/CONCEPT_SYNONYM.csv' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', QUOTE E'\b');

\copy omop.drug_strength FROM '/docker-entrypoint-initdb.d/DRUG_STRENGTH.csv' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', QUOTE E'\b');