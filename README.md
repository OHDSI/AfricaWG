

## 🏗️ Setting Up the Project

Follow these steps to get the project up and running:

### 1. Clone the repository

```bash
git clone git@github.com:jayasanka-sack/openmrs-to-omop.git
cd openmrs-to-omop
```

---

### 2. Build the Required Images

Run the following command to build the `omop-etl-core` and `omop-etl-achilles` images:

```bash
docker compose --profile manual build
```

---

### 3. Start the services

```bash
docker compose up
```

---

### 4. Clone the production database
```bash
docker compose run --rm core clone-openmrs-db
```

### 5. Map OpenMRS Concepts to OMOP Standard Concepts

This step involves mapping your OpenMRS concepts to OMOP standard concepts using the Usagi tool. This mapping is crucial for ensuring that your OpenMRS data is correctly transformed into the OMOP Common Data Model.

> **Note:** For your convenience, example mappings are provided in the `concepts` directory. If you're here to explore the project, you can skip this step and use the provided example mappings. This step is only required when working with a production environment or when connecting a different OpenMRS database.

---

#### 5.1. Generate the Usagi Input File

Run the following command:

```bash
docker compose run --rm core generate-concepts-usagi-input
```

This will generate a CSV file containing OpenMRS concept IDs, names, and their usage frequencies.

✅ **Location of the generated file:**

```
/concepts/concepts_for_usagi_mapping
```

You'll import this file into **Usagi** to map your OpenMRS concepts to OMOP standard concepts.

---

#### 5.2. Import the File into Usagi

##### a. Download and Install Usagi

If you don't have Usagi installed yet:

- Go to the official OHDSI page for Usagi:
  [https://ohdsi.github.io/Usagi/](https://ohdsi.github.io/Usagi/)
- Download the latest release suitable for your operating system.
- Extract and run Usagi.

---

##### b. Import the OMOP Vocabulary

Before you can map your concepts, you must load the OMOP vocabulary into Usagi.

- Download the vocabulary files (e.g. `CONCEPT.csv`, `VOCABULARY.csv`, etc.) from [OHDSI Athena](https://athena.ohdsi.org/).
- In Usagi, go to:

```
File > Import Vocabulary
```

- Select the folder containing the vocabulary CSV files.

> **Note:** This is a one-time task unless you update your vocabularies in the future.

---

##### c. Import the Concepts for Mapping

- In Usagi, go to:

```
File > Import Codes
```

- Select the file you generated in Step 5.1:

```
/concepts/concepts_for_usagi_mapping
```

Usagi will automatically attempt to map your source concepts to standard OMOP concepts based on the concept names and frequencies.

---

##### d. Review and Save the Mapping

- Review the suggested mappings:
    - Approve mappings
    - Change mappings
    - Or leave some unmapped for later

- Once you're done, save the mapping:

![](docs/img/usagi.jpeg)
```
File > Save As
```

- Save the file in the `concepts` folder and name it:

```
mapping.csv
```

**Location of saved mapping file:**

```
/concepts/mapping.csv
```

This file will later be used by **SQLMesh** during ETL processing.

---

##### e. Updating Your Mapping Later

If you wish to change mappings in the future:

- Open Usagi
- Go to:

```
File > Apply Previous Mapping
```

- Import your existing mapping file (`mapping.csv`), and make further edits as needed.




### 6. **Run the core service to convert the data**

You have two options to run the data conversion:

#### Option 1: Run the Full Pipeline

Execute all steps automatically in the correct order:

```bash
docker compose run --rm core run-full-pipeline
```

#### Option 2: Run Commands Step-by-Step

If you prefer to run commands individually, follow the order specified here:

```bash
# Step 1: Apply SQLMesh plan
docker compose run --rm core apply-sqlmesh-plan

# Step 2: Materialize MySQL views
docker compose run --rm core materialize-mysql-views

# Step 3: Migrate to PostgreSQL
docker compose run --rm core migrate-to-postgresql

# Step 4: Import OMOP concepts
docker compose run --rm core import-omop-concepts

# Step 5: Apply OMOP constraints
docker compose run --rm core apply-omop-constraints

# Step 6: Populate CDM source
docker compose run --rm core populate-cdm-source
```

**Note:** The order of commands is important. Refer to `core/entrypoint.sh` for the exact sequence used in the full pipeline.

---

**Available Commands**

| Command                         | Description                                                                                                                        |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------|
| `clone-openmrs-db`              | Clones the OpenMRS database from a configured source into the `openmrs` MySQL database inside the container.                       |
| `generate-concepts-usagi-input` | Generates a list of concepts to import to Usagi.                                                                                   |
| `apply-sqlmesh-plan`            | Runs the SQLMesh plan with `--no-prompts` and auto-applies changes.                                                                |
| `materialize-mysql-views`       | Extracts all views from the `omop_db` MySQL schema and materializes them as physical tables into the `public` schema.              |
| `migrate-to-postgresql`         | Migrates the materialized MySQL database to PostgreSQL using `pgloader`, recreating the target PostgreSQL DB and loading OMOP DDL. |
| `import-omop-concepts`          | Imports OMOP vocabulary/concept CSVs (`CONCEPT_CLASS`, `DOMAIN`, `VOCABULARY`, and `CONCEPT`) into the PostgreSQL database.        |
| `apply-omop-constraints`        | Executes SQL constraint scripts from `omop-ddl/processed/constraints/` against the PostgreSQL database.                            |
| `populate-cdm-source`           | Populates the CDM source metadata table with configuration details.                                                                |
| `run-full-pipeline`             | Executes all steps automatically in the correct order (see `core/entrypoint.sh` for details).                                      |

### 7. **Run Achilles to generate data summaries** (Check What Achilles does below.)
   ```
   docker compose run achilles
   ```
### 8. **Run DQD to perform data quality checks**
   This runs the [OHDSI Data Quality Dashboard (DQD)](https://github.com/OHDSI/DataQualityDashboard) on the OMOP database.
   ```bash
    docker compose run --rm dqd run
   ```
### 9. **View the Data Quality Dashboard**
      This serves the DQD results on a local web server. Once it's running, open your browser and go to [http://localhost:3000](http://localhost:3000).
   ```
   docker compose run --rm --service-ports dqd view
   ``` 

## 🧪 What does Achilles do?
Achilles analyzes the OMOP CDM data and generates summary statistics, data quality metrics, and precomputed reports. These results are essential for visualizations in tools like Atlas.

When you run:

```
docker compose run achilles
```
- ✅ It connects to your omop-db
- ✅ Scans and summarizes data in the public schema
- ✅ Produces results in the Achilles_results and Achilles_analysis tables
- ✅ Prepares your OMOP CDM for use with the web-based Atlas UI

## 🏥 Optional: Run with OpenMRS Instance
If you want to have an OpenMRS instance up and running alongside the ETL pipeline, you can use the `docker-compose.openmrs.yml` override file.

### To start with OpenMRS:
```bash
docker compose -f docker-compose.yml -f docker-compose.openmrs.yml up
```

This will launch an OpenMRS instance accessible at:
👉 http://localhost/

This is useful if you want to interact with OpenMRS directly, add test data, or verify the source data while running the ETL pipeline.

---

## 🌀 Optional: Run with Airflow
You can run this project with Apache Airflow to visually orchestrate and schedule your data pipeline.

### To start with Airflow:
```bash
docker compose -f docker-compose.yml -f docker-compose.airflow.yml up
```

This will launch the Airflow UI at:
👉 http://localhost:8080

Login credentials:\
Username: airflow\
Password: airflow

You can use the UI to manually trigger DAGs that run your pipeline steps.
![](docs/img/airflow.jpeg)

---

## 🔌 Connecting Your Own OpenMRS Database

By default, this setup uses the `openmrs/openmrs-reference-application-3-db:nightly-with-data` image as a preloaded source database (`omrsdb` service).
If you want to connect your own OpenMRS database (either remote or local), follow these steps:

### 1. Remove the bundled OpenMRS DB service

In your `docker-compose.yml`, remove or comment out the entire **`omrsdb`** section:

```yaml
# omrsdb:
#   image: openmrs/openmrs-reference-application-3-db:nightly-with-data
#   ports:
#     - "3306:3306"
```

### 2. Update the `core` service environment variables

In the `core` service, set your database connection details under the `environment` section.

Example for a **remote MySQL database**:

```yaml
core:
  environment:
    SRC_HOST: your-db-hostname-or-ip
    SRC_PORT: 3306
    SRC_USER: your-db-username
    SRC_PASS: your-db-password
    SRC_DB: your-db-name
```

Example:

```yaml
SRC_HOST: my-openmrs-db.example.com
SRC_PORT: 3306
SRC_USER: openmrs_user
SRC_PASS: strongpassword123
SRC_DB: openmrs_prod
```

### 3. Remove `omrsdb` from dependencies

In the `core` service, update `depends_on` to remove `omrsdb` since it no longer exists:

```yaml
depends_on:
  - sqlmesh-db
  - omop-db
```

### 4. Start the services

Run:

```bash
docker-compose up -d
```

This will start the ETL components using your specified OpenMRS database as the source.

---

## Setting Up Git LFS for This Repository

This repository uses **Git Large File Storage (LFS)** to handle large files like `CONCEPT.csv`. If you're cloning or pulling the repository, make sure to set up Git LFS to download the actual files instead of pointers.

### Step 1: Install Git LFS
Before cloning, install Git LFS:

- **macOS (Homebrew)**  
  ```sh
  brew install git-lfs
  ```

- **Linux (Ubuntu/Debian)**
  ```sh
  sudo apt update && sudo apt install git-lfs
  ```

- **Windows**  
  Download and install Git LFS from [Git LFS official site](https://git-lfs.github.com/).

### Step 2: Clone the Repository
After installing Git LFS, clone the repository:

```sh
git clone https://github.com/jayasanka-sack/openmrs-to-omop.git
cd openmrs-to-omop
```

Git LFS will automatically download the large files.

### Step 3: Pulling Updates
If you have already cloned the repository before installing Git LFS, or if you are pulling new changes, run:

```sh
git lfs install
git lfs pull
```

This ensures all large files are properly downloaded.

### Troubleshooting
If you see pointer files instead of actual data when opening a large file (e.g., `CONCEPT.csv`), it means Git LFS is not set up correctly. Run:

```sh
git lfs pull
```

For more information, refer to the [Git LFS documentation](https://git-lfs.github.com/).
