import os
import pandas as pd
from sqlalchemy import create_engine


MYSQL_USER = os.environ.get("MYSQL_USER", "root")
MYSQL_PASSWORD = os.environ.get("MYSQL_PASSWORD", "openmrs")
MYSQL_HOST = os.environ.get("MYSQL_HOST", "sqlmesh-db")
MYSQL_PORT = os.environ.get("MYSQL_PORT", "3306")
MYSQL_DB = os.environ.get("MYSQL_DATABASE", "openmrs")

# Build connection string
connection_string = f"mysql+pymysql://{MYSQL_USER}:{MYSQL_PASSWORD}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}"

# Create SQLAlchemy engine
engine = create_engine(connection_string)

query = """
        WITH CombinedFrequencies AS (
            -- 1a. Obs Questions
            SELECT concept_id, COUNT(*) AS freq, 'Obs Question' AS source
            FROM obs WHERE voided = 0 AND concept_id IS NOT NULL GROUP BY concept_id
            UNION ALL
            -- 1b. Obs Coded Answers
            SELECT value_coded AS concept_id, COUNT(*) AS freq, 'Obs Answer' AS source
            FROM obs WHERE voided = 0 AND value_coded IS NOT NULL GROUP BY value_coded
            UNION ALL
            -- 3. Drug Orders
            SELECT o.concept_id, COUNT(*) AS freq, 'Drug Order' AS source
            FROM orders o WHERE o.voided = 0 AND o.order_type_id = 2 GROUP BY o.concept_id
            UNION ALL
            -- 4. Test Orders
            SELECT o.concept_id, COUNT(*) AS freq, 'Test Order' AS source
            FROM orders o WHERE o.voided = 0 AND o.order_type_id = 3 GROUP BY o.concept_id
            UNION ALL
            -- 5. Conditions
            SELECT condition_coded AS concept_id, COUNT(*) AS freq, 'Condition' AS source
            FROM conditions WHERE voided = 0 AND condition_coded IS NOT NULL GROUP BY condition_coded
            UNION ALL
            -- 6. Allergies
            SELECT coded_allergen AS concept_id, COUNT(*) AS freq, 'Allergen' AS source
            FROM allergy WHERE voided = 0 AND coded_allergen IS NOT NULL GROUP BY coded_allergen
            UNION ALL
            -- 7. Allergy Reactions
            SELECT reaction_concept_id AS concept_id, COUNT(*) AS freq, 'Allergen Reaction' AS source
            FROM allergy_reaction WHERE reaction_concept_id IS NOT NULL GROUP BY reaction_concept_id
            UNION ALL
            -- 8. Program Workflow States
            SELECT pws.concept_id, COUNT(*) AS freq, 'Program State' AS source
            FROM patient_state ps JOIN program_workflow_state pws ON ps.state = pws.program_workflow_state_id WHERE ps.voided = 0 GROUP BY pws.concept_id
        ),
             AggregatedFrequency AS (
                 SELECT concept_id, SUM(freq) AS total_freq
                 FROM CombinedFrequencies
                 GROUP BY concept_id
                 HAVING SUM(freq) >=1  -- Filter singletons directly at aggregation step
             ),
             RankedNames AS (
                 SELECT concept_id, name,
                        ROW_NUMBER() OVER (
                    PARTITION BY concept_id
                    ORDER BY
                        CASE WHEN locale = 'en' AND concept_name_type = 'FULLY_SPECIFIED' AND voided = 0 THEN 1
                             WHEN locale = 'en' AND voided = 0 THEN 2
                             WHEN voided = 0 THEN 3
                             ELSE 4
                            END
                    ) AS name_rank
                 FROM concept_name
             ),
             RankedMappings AS (
                 SELECT c.concept_id,
                        c.retired AS is_retired,
                        rn.name AS concept_name,
                        cl.name AS concept_class,
                        rs.name AS source_system,
                        rt.code AS source_code,
                        ROW_NUMBER() OVER (
                    PARTITION BY c.concept_id
                    ORDER BY
                        CASE WHEN rs.name = 'CIEL' THEN 1
                             WHEN rs.name IS NOT NULL THEN 2
                             ELSE 3
                            END
                    ) AS rank_id
                 FROM concept c
                          LEFT JOIN RankedNames rn ON c.concept_id = rn.concept_id AND rn.name_rank = 1
                          LEFT JOIN concept_class cl ON c.class_id = cl.concept_class_id
                          LEFT JOIN concept_reference_map crm ON c.concept_id = crm.concept_id
                          LEFT JOIN concept_reference_term rt ON crm.concept_reference_term_id = rt.concept_reference_term_id AND rt.retired = 0
                          LEFT JOIN concept_reference_source rs ON rt.concept_source_id = rs.concept_source_id
             )
        SELECT cf.concept_id               AS source_concept_id,
               rm.concept_name             AS source_concept_name,
               rm.is_retired               AS is_retired,
               rm.concept_class            AS type,
               rm.source_system            AS "Reference code system",
               rm.source_code              AS "Reference code",
               cf.total_freq               AS frequency
        FROM AggregatedFrequency cf
                 LEFT JOIN RankedMappings rm ON cf.concept_id = rm.concept_id AND rm.rank_id = 1
        ORDER BY frequency DESC;
"""

# Execute SQL and fetch into DataFrame
df = pd.read_sql(query, engine)

df["frequency"] = df["frequency"].astype("Int64")

file_path = "/concepts/concepts_for_usagi_mapping.csv"

# Remove the file if it exists
if os.path.exists(file_path):
    os.remove(file_path)
    print(f"Successfully deleted {file_path}")
else:
    print(f"File {file_path} does not exist.")

# 1. Export CSV
df.to_csv(file_path, index=False)

# 2. Set file permissions to rw-rw-r-- (User: Read/Write, Group: Read/Write, Others: Read)
os.chmod(file_path, 0o664)
