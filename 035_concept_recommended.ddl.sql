set search_path  = public;

CREATE TABLE IF NOT EXISTS concept_recommended
(
    concept_id_1 bigint,
    concept_id_2 bigint,
    relationship_id character varying(20)
)