
# 🌀 5.0 Run Orchestration

You have two options to run the data conversion:

## Option A: Production Orchestration (Airflow)

Use **Apache Airflow** to visually monitor and schedule your pipeline.

### 1. Environment Setup

```bash
chmod +x ./airflow/airflow_env_generator.sh && ./airflow/airflow_env_generator.sh
```

### 2. Launch Airflow

```bash
sudo docker compose --env-file .env-airflow -f docker-compose.airflow.yml up -d
```

- UI URL: http://localhost:8780
- Credentials: username: `airflow` password: `airflow`

![](docs/img/airflow.png)

### 3. Trigger Setup DAG:

Run `OMOP_Vocabulary_Load`.

This DAG manages the end-to-end ingestion and semantic mapping of medical vocabularies. It executes the following core
processes:

- Athena Vocabulary Ingestion: Performs a bulk import of Athena vocabulary concepts into the `omop` database. This
  provides the necessary underlying structure for Atlas to function.
- Semantic Mapping Workflow: Processes source codes through a decision logic (as seen in the workflow diagram at the
  start of readme) to determine the best OMOP Standard Concept.
- OCL/Athena Mapper Integration: For codes identified as CIEL or those lacking immediate standard maps, the OCL/Athena
  Mapper is engaged. It cross-references OCL and Athena relationships to resolve mappings, resulting in two distinct
  output files:

    - `success_concept_mappings.csv`: Contains automated maps for direct implementation.
    - `concepts_for_usagi_mapping.csv`: Contains concepts that require human-in-the-loop validation via the Usagi tool
      or manual Athena lookup.

![](docs/img/ocl_mapper_worklow.png)

### 4. Next Step:

Proceed to Section 6.0 (Mapping) before running clinical DAG.

---
