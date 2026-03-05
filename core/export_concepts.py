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
SELECT
    c.concept_id AS sourceCode,
    cn.name AS sourceName,
    COUNT(o.obs_id) AS frequency
FROM concept c
JOIN concept_name cn
    ON cn.concept_id = c.concept_id
    AND cn.locale = 'en'
    AND cn.locale_preferred = 1
LEFT JOIN obs o
    ON o.concept_id = c.concept_id
GROUP BY c.concept_id, cn.name
ORDER BY frequency DESC;
"""

# Execute SQL and fetch into DataFrame
df = pd.read_sql(query, engine)

# Save to CSV
df.to_csv("/concepts/concepts_for_usagi_mapping.csv", index=False)

print("✅ CSV exported as concepts_for_usagi_mapping.csv")
