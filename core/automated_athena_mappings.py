import logging
import os
import sys
import pandas as pd
import requests
from sqlalchemy import create_engine, text, bindparam

MYSQL_USER = "root"
MYSQL_PASSWORD = "openmrs"
MYSQL_HOST = os.getenv("SQLMESH_DB", "sqlmesh-db")
MYSQL_PORT = os.getenv("MYSQL_PORT", "3306")
MYSQL_DATABASE = "openmrs"

TARGET_HOST = "omop-db"
TARGET_USER = "postgres"
TARGET_PASSWORD = "postgres_pass"
TARGET_PORT = "5432"
TARGET_DB = "postgres"
TARGET_SCHEMA = "public"

MYSQL_URL = f"mysql+pymysql://{MYSQL_USER}:{MYSQL_PASSWORD}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DATABASE}"
PG_URL = f"postgresql+psycopg2://{TARGET_USER}:{TARGET_PASSWORD}@{TARGET_HOST}:{TARGET_PORT}/{TARGET_DB}?options=-csearch_path={TARGET_SCHEMA}"

CONCEPT_DIR = "../concepts/"
AUTO_GEN_MAPPINGS = os.path.join(CONCEPT_DIR, "success_concept_mappings.csv")
USAGI_MAPPING_FILE = os.path.join(CONCEPT_DIR, "concepts_for_usagi_mapping.csv")

OCL_API_URL = "https://api.openconceptlab.org/orgs/CIEL/sources/CIEL/concepts/"

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s - %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)

CHUNK_SIZE = 500  # Bumped chunk size up since we're batching queries now

VOCAB_MAP = {
    'CIEL': 'CIEL', 'SNOMED CT': 'SNOMED', 'SNOMED MVP': None, 'LOINC': 'LOINC',
    'ICD-10-WHO': 'ICD10', 'ICD-10': 'ICD10', 'RxNORM': 'RxNorm', 'PIH': 'CIEL',
    'AMPATH': 'CIEL', 'ICPC2': 'ICPC2'
}

TRIAGE_PRIORITY = {'MAPPED': 1, 'MULTIPLE_WITH_PRIMARY': 2, 'AMBIGUOUS_MULTIPLE': 3, 'UNMAPPED': 99}
DOMAIN_VOCAB_PRIORITY = {
    'Drug': {'RxNorm': 1, 'CVX': 2, 'SNOMED': 3,"RxNorm Extension": 4},
    'Measurement': {'LOINC': 1, 'SNOMED': 2},
    'Condition': {'SNOMED': 1, 'ICD10': 2}
}
DEFAULT_VOCAB_PRIORITY = {'RxNorm': 1, 'CVX': 2, 'SNOMED': 3, 'LOINC': 4, 'ICD10': 5}
SUCCESS_STATUSES = ['SUCCESS_ATHENA', 'SUCCESS_PRIMARY_SELECTED', 'SUCCESS_OCL_ATHENA', 'SUCCESS_NAME_MATCH',
                    'SUCCESS_NAME_MATCH_VIA_MAP']

UNIT_CLEANER = {
    "beats/min": "beats/minute", "bpm": "beats/minute", "mmol/l": "mmol/L",
    "u/l": "U/L", "iu/l": "IU/L", "percent": "%", "percentage": "%"
}

# Reusable HTTP Client Session to save handshakes
http_session = requests.Session()
ocl_cache = {}


def typecasting_floats(value):
    if pd.isna(value) or value == '' or value is None:
        return None
    return int(float(value))


# =========================
# QUERIES
# =========================
OPENMRS_EXTRACT_QUERY = text("""
                             WITH ConceptFrequency AS (SELECT concept_id, COUNT(*) AS freq
                                                       FROM obs
                                                       WHERE voided = 0
                                                       GROUP BY concept_id),
                                  RankedMappings AS (SELECT c.concept_id,
                                                            cn.name AS   concept_name,
                                                            cl.name AS   concept_class,
                                                            rs.name AS   source_system,
                                                            rt.code AS   source_code,
                                                            ROW_NUMBER() OVER (
                    PARTITION BY c.concept_id 
                    ORDER BY CASE WHEN rs.name = 'CIEL' THEN 1 WHEN rs.name IS NOT NULL THEN 2 ELSE 3 END
               ) AS rank_id
                                                     FROM concept c
                                                              LEFT JOIN concept_name cn
                                                                        ON c.concept_id = cn.concept_id AND
                                                                           cn.locale = 'en' AND
                                                                           cn.concept_name_type = 'FULLY_SPECIFIED' AND
                                                                           cn.voided = 0
                                                              LEFT JOIN concept_class cl ON c.class_id = cl.concept_class_id
                                                              LEFT JOIN concept_reference_map crm ON c.concept_id = crm.concept_id
                                                              LEFT JOIN concept_reference_term rt
                                                                        ON crm.concept_reference_term_id = rt.concept_reference_term_id
                                                              LEFT JOIN concept_reference_source rs
                                                                        ON rt.concept_source_id = rs.concept_source_id
                                                     WHERE c.retired = 0)
                             SELECT rm.concept_id              AS source_concept_id,
                                    rm.concept_name            AS source_concept_name,
                                    rm.concept_class           AS type,
                                    rm.source_system           AS "Reference code system",
                                    rm.source_code             AS "Reference code",
                                    COALESCE(cf.freq, 0)       AS frequency,
                                    CASE
                                        WHEN rm.source_system = 'CIEL' THEN 'MAPPED TO CIEL'
                                        WHEN rm.source_system IS NOT NULL THEN 'MAPPED OTHER'
                                        ELSE 'TRUE ORPHAN' END AS "Mapping Status"
                             FROM RankedMappings rm
                                      LEFT JOIN ConceptFrequency cf ON rm.concept_id = cf.concept_id
                             WHERE rm.rank_id = 1
                             ORDER BY frequency DESC;
                             """)

ATHENA_BATCH_LOOKUP_QUERY = text("""
                                 SELECT c1.concept_id                                    AS   athena_source_id,
                                        c1.concept_code                                  AS   source_code,
                                        c1.concept_name                                  AS   source_name,
                                        c1.vocabulary_id                                 AS   source_vocab,
                                        c1.domain_id                                     AS   source_domain,
                                        COALESCE(c2.concept_id, 0)                       AS   target_concept_id,
                                        COALESCE(c2.concept_name, 'No matching concept') AS   target_name,
                                        COALESCE(c2.vocabulary_id, 'NONE')               AS   target_vocab,
                                        COALESCE(c2.domain_id, c1.domain_id)             AS   target_domain,
                                        CASE
                                            WHEN c2.concept_id IS NULL THEN 'UNMAPPED'
                                            WHEN COUNT(c2.concept_id) OVER (PARTITION BY c1.concept_id) = 1 THEN 'MAPPED'
                                            WHEN COUNT(c2.concept_id) OVER (PARTITION BY c1.concept_id) > 1 AND
                                        COUNT(CASE WHEN c2.standard_concept = 'S' THEN 1 END) OVER (PARTITION BY c1.concept_id) = 1 THEN 'MULTIPLE_WITH_PRIMARY'
                ELSE 'AMBIGUOUS_MULTIPLE'
                                 END
                                 AS triage_status
    FROM concept c1
    LEFT JOIN concept_relationship cr ON c1.concept_id = cr.concept_id_1 AND cr.relationship_id IN ('Maps to', 'Non-standard to Standard map (OMOP)') AND cr.invalid_reason IS NULL
    LEFT JOIN concept c2 ON cr.concept_id_2 = c2.concept_id AND c2.standard_concept = 'S' AND c2.invalid_reason IS NULL
    WHERE (c1.concept_code, c1.vocabulary_id) IN :code_vocab_pairs;
                                 """).bindparams(bindparam("code_vocab_pairs", expanding=True))

# BATCHED Name Lookup Query
ATHENA_BATCH_NAME_QUERY = text("""
                               WITH MatchedConcepts AS (SELECT concept_id,
                                                               concept_name,
                                                               vocabulary_id,
                                                               domain_id,
                                                               concept_code,
                                                               standard_concept,
                                                               ROW_NUMBER() OVER (
                   PARTITION BY LOWER(concept_name)
                   ORDER BY 
                       CASE 
                           WHEN LOWER(domain_id) = 'condition' THEN 1
                           WHEN LOWER(domain_id) = 'drug' THEN 1
                           WHEN LOWER(domain_id) = 'measurement' THEN 1
                           ELSE 3
                       END ASC,
                       CASE WHEN standard_concept = 'S' THEN 1 ELSE 2 END ASC
               ) as rank_id
                                                        FROM concept
                                                        WHERE LOWER(concept_name) IN :concept_names
                                                          AND invalid_reason IS NULL)
                               SELECT LOWER(mc.concept_name)                                    AS search_key,
                                      CASE
                                          WHEN mc.standard_concept = 'S' THEN mc.concept_id
                                          ELSE COALESCE(c2.concept_id, mc.concept_id) END       AS target_concept_id,
                                      CASE
                                          WHEN mc.standard_concept = 'S' THEN mc.concept_name
                                          ELSE COALESCE(c2.concept_name, mc.concept_name) END   AS target_name,
                                      CASE
                                          WHEN mc.standard_concept = 'S' THEN mc.vocabulary_id
                                          ELSE COALESCE(c2.vocabulary_id, mc.vocabulary_id) END AS target_vocab,
                                      CASE
                                          WHEN mc.standard_concept = 'S' THEN mc.domain_id
                                          ELSE COALESCE(c2.domain_id, mc.domain_id) END         AS target_domain,
                                      mc.concept_code                                           AS target_code,
                                      CASE
                                          WHEN mc.standard_concept = 'S' THEN 'SUCCESS_NAME_MATCH'
                                          WHEN c2.concept_id IS NOT NULL THEN 'SUCCESS_NAME_MATCH_VIA_MAP'
                                          ELSE 'NON_STANDARD_TAKEUP' END                        AS derived_status
                               FROM MatchedConcepts mc
                                        LEFT JOIN concept_relationship cr ON mc.concept_id = cr.concept_id_1 AND
                                                                             cr.relationship_id IN ('Maps to',
                                                                                                    'Non-standard to Standard map (OMOP)') AND
                                                                             cr.invalid_reason IS NULL
                                        LEFT JOIN concept c2
                                                  ON cr.concept_id_2 = c2.concept_id AND c2.standard_concept = 'S' AND
                                                     c2.invalid_reason IS NULL
                               WHERE mc.rank_id = 1;
                               """).bindparams(bindparam("concept_names", expanding=True))


def get_ocl_mapping(concept_code):
    if concept_code in ocl_cache:
        return ocl_cache[concept_code]
    try:
        response = http_session.get(f"{OCL_API_URL}{concept_code}/", timeout=3)
        if response.status_code != 200:
            return None
        mappings = response.json().get('mappings', [])
        for m in mappings:
            if m.get('map_type') in ['SAME-AS', 'MAPS-TO']:
                to_source_url = m.get('to_source_url')
                if to_source_url:
                    target_vocab = to_source_url.split('/')[-2].split('-')[0].upper()
                    res = {"code": m.get('to_concept_code'), "vocab": target_vocab}
                    ocl_cache[concept_code] = res
                    return res
    except Exception as e:
        logger.error(f"OCL ERROR for code {concept_code}: {e}")
    return None


def calculate_vocab_priority(domain, vocab):
    domain_priorities = DOMAIN_VOCAB_PRIORITY.get(domain)
    if domain_priorities:
        return domain_priorities.get(vocab, 99)
    return DEFAULT_VOCAB_PRIORITY.get(vocab, 99)


def rank_athena_results(df):
    if df.empty: return df
    df['triage_rank'] = df['triage_status'].map(lambda x: TRIAGE_PRIORITY.get(x, 99))
    df['vocab_rank'] = df.apply(lambda row: calculate_vocab_priority(row['source_domain'], row['target_vocab']), axis=1)
    df = df.sort_values(['source_code', 'triage_rank', 'vocab_rank'])
    return df.drop_duplicates(subset=['source_code', 'source_vocab', 'target_concept_id'], keep='first')


def run_concepts_semantic_mapping():
    logger.info("Starting OpenMRS -> OMOP semantic mapping pipeline")
    try:
        my_engine = create_engine(MYSQL_URL)
        pg_engine = create_engine(PG_URL)

        logger.info("Extracting OpenMRS concepts")
        with my_engine.connect() as conn:
            df = pd.read_sql(OPENMRS_EXTRACT_QUERY, conn)
        logger.info(f"Extracted {len(df)} concepts")

        df['athena_vocab'] = df['Reference code system'].map(lambda x: VOCAB_MAP.get(x, x))
        all_results = []

        with pg_engine.connect() as pg_conn:
            for start in range(0, len(df), CHUNK_SIZE):
                chunk = df.iloc[start:start + CHUNK_SIZE].copy()
                logger.info(f"Processing chunk {start} - {start + len(chunk)}")

                valid_chunk = chunk[chunk['Mapping Status'] != 'TRUE ORPHAN']
                pairs = list(valid_chunk[['Reference code', 'athena_vocab']].dropna(
                    subset=['Reference code', 'athena_vocab']).itertuples(index=False, name=None))

                athena_lookup = {}
                if pairs:
                    result = pg_conn.execute(ATHENA_BATCH_LOOKUP_QUERY, {"code_vocab_pairs": tuple(pairs)})
                    athena_df = pd.DataFrame(result.fetchall(), columns=result.keys())
                    athena_df = rank_athena_results(athena_df)
                    for _, row_ath in athena_df.iterrows():
                        key = (str(row_ath['source_code']), str(row_ath['source_vocab']))
                        athena_lookup.setdefault(key, []).append(row_ath.to_dict())

                # Prepare for Batch Name Lookups down the pipeline line
                names_to_lookup = []
                for _, row in chunk.iterrows():
                    if not athena_lookup.get((str(row.get('Reference code', '')), str(row.get('athena_vocab', '')))) and \
                            row['Reference code system'] != 'CIEL':
                        name_str = str(row.get('source_concept_name', '')).strip()
                        if name_str:
                            names_to_lookup.append(UNIT_CLEANER.get(name_str.lower(), name_str.lower()))

                name_lookup_dict = {}
                if names_to_lookup:
                    name_res = pg_conn.execute(ATHENA_BATCH_NAME_QUERY, {"concept_names": tuple(set(names_to_lookup))})
                    name_df = pd.DataFrame(name_res.fetchall(), columns=name_res.keys())

                    if not name_df.empty:
                        # Drop duplicate search keys, keeping the first one (which matches our SQL ORDER BY priority)
                        name_df = name_df.drop_duplicates(subset=['search_key'], keep='first')
                        name_lookup_dict = name_df.set_index('search_key').to_dict(orient='index')
                # Route Records
                for _, row in chunk.iterrows():
                    ref_code = str(row.get('Reference code', ''))
                    ath_vocab = str(row.get('athena_vocab', ''))
                    concept_name = str(row.get('source_concept_name', '')).strip()

                    athena_matches = athena_lookup.get((ref_code, ath_vocab))

                    if athena_matches:
                        for athena_match in athena_matches:
                            record = row.to_dict()
                            triage = athena_match.get('triage_status')
                            is_standard = athena_match.get('target_concept_id', 0) != 0
                            target_id = athena_match['target_concept_id'] if is_standard else athena_match[
                                'athena_source_id']

                            record.update({
                                "target_name": athena_match.get('target_name'),
                                "target_vocab": athena_match.get('target_vocab'),
                                "target_domain": athena_match.get('target_domain'),
                                "target_concept_id": typecasting_floats(target_id),
                                "match_status": "SUCCESS_ATHENA" if triage == 'MAPPED' and is_standard else "SUCCESS_MULTIPLE_MAPPED" if triage == 'AMBIGUOUS_MULTIPLE' and is_standard else "SUCCESS_PRIMARY_SELECTED" if triage == 'MULTIPLE_WITH_PRIMARY' and is_standard else "NON_STANDARD_TAKEUP" if not is_standard else "FAILED_ATHENA"
                                # "match_status": "SUCCESS_ATHENA" if triage in ['MAPPED',
                                #                                                'AMBIGUOUS_MULTIPLE'] and is_standard else "SUCCESS_PRIMARY_SELECTED" if triage == 'MULTIPLE_WITH_PRIMARY' else "NON_STANDARD_TAKEUP" if not is_standard else "FAILED_ATHENA"
                            })
                            all_results.append(record)

                    elif row['Reference code system'] == 'CIEL':
                        record = row.to_dict()
                        ocl_res = get_ocl_mapping(ref_code)
                        if ocl_res:
                            ocl_query = pg_conn.execute(ATHENA_BATCH_LOOKUP_QUERY, {
                                "code_vocab_pairs": ((str(ocl_res['code']), str(ocl_res['vocab'])),)})
                            ocl_result = ocl_query.mappings().fetchone()
                            if ocl_result:
                                target_id = ocl_result['target_concept_id'] if ocl_result['target_concept_id'] != 0 else \
                                ocl_result['athena_source_id']
                                record.update({
                                    "target_name": ocl_result['target_name'],
                                    "target_vocab": ocl_result['target_vocab'],
                                    "target_domain": ocl_result['target_domain'],
                                    "target_concept_id": typecasting_floats(target_id),
                                    "match_status": "SUCCESS_OCL_ATHENA"
                                })
                            else:
                                record.update({"target_concept_id": 0, "match_status": "FAILED_ATHENA_POST_OCL"})
                        else:
                            record.update({"target_concept_id": 0, "match_status": "FAILED_OCL_API"})
                        all_results.append(record)

                    else:
                        record = row.to_dict()
                        clean_key = UNIT_CLEANER.get(concept_name.lower().strip(), concept_name.lower().strip())
                        name_match = name_lookup_dict.get(clean_key)

                        if name_match:
                            record.update({
                                "Reference code": name_match['target_code'], "target_name": name_match['target_name'],
                                "target_vocab": name_match['target_vocab'],
                                "target_domain": name_match['target_domain'],
                                "target_concept_id": typecasting_floats(name_match['target_concept_id']),
                                "match_status": name_match['derived_status']
                            })
                        else:
                            record.update({"target_concept_id": 0, "match_status": "USAGI_REQUIRED"})
                        all_results.append(record)

        # File Generation
        final_df = pd.DataFrame(all_results)
        os.makedirs(CONCEPT_DIR, exist_ok=True)
        final_df[final_df['match_status'].isin(SUCCESS_STATUSES)].to_csv(AUTO_GEN_MAPPINGS, index=False)
        final_df[~final_df['match_status'].isin(SUCCESS_STATUSES)].to_csv(USAGI_MAPPING_FILE, index=False)

        logger.info("-" * 50)
        logger.info("MATCH STATUS SUMMARY")
        logger.info("-" * 50)
        logger.info(f"\n{final_df['match_status'].value_counts()}")
        logger.info("-" * 50)
        logger.info("Pipeline completed successfully")

    except Exception as e:
        logger.error(f"CRITICAL ERROR: {str(e)}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    run_concepts_semantic_mapping()
