# OMOP ETL Deep Dive - Getting Started Guide

This project helps you transform healthcare data from OpenMRS into the OMOP Common Data Model format using **SQLMesh** as the transformation engine.

## 📹 Session Recording

This entire setup and workflow was covered in our previous call. You can watch the full recording here:
**[OHDSI Africa Chapter - OMOP ETL Deep Dive Session](https://drive.google.com/file/d/1Ew2O4O8-GIYwnIU76tOPYQGcs5BQMfpk/view?usp=drive_link)**

Here is the link to the github repository with the guided steps:
https://github.com/abertnamanya/openmrs-350-patients-dataset
## Your Goal

We've already mapped two entities during the call (**Location** and **Person**) - you can find these examples in the `core/models` folder. Your task is to **map the remaining OMOP entities** using these as reference templates.

**Dataset Info:** You'll be working with a sample OpenMRS database containing **350 patients** to practice your transformations.



## Quick Start (3 Simple Steps)

### Step 1: Get the Project Files
ETL executions files will be downloaded onto you're PC/MAC
```bash
git clone --branch omop-deep-dive --single-branch https://github.com/OHDSI/AfricaWG.git
cd AfricaWG
```

### Step 2: Build the Project

This step prepares all the necessary software components. It may take 5-10 minutes the first time.

```bash
docker compose --profile manual build
```

**What this does:** Downloads and sets up all the databases and tools you'll need.

### Step 3: Start Everything

```bash
docker compose up -d
```

**What this does:** Starts all the services including databases and web interfaces.

---

## Working with Your Data

### Understanding the Database Setup

You now have three main databases:
- **PostgreSQL** (omop-db): Your final OMOP-formatted data lives here
- **MySQL** (sqlmesh-db): Contains two databases:
    - `openmrs`: Your source OpenMRS dataset with 350 patients
    - `omop_db`: Used for quick previews and intermediate processing

### Viewing Your Data with CloudBeaver

CloudBeaver is a web-based tool that lets you explore your databases without needing to install additional software.

#### First Time Setup (Only do this once)

1. **Open CloudBeaver**: Go to http://localhost:8978 in your web browser

2. **Create Your Admin Account** (First time only):
    - You'll see a Setup Wizard
    - Choose any username (suggestion: `superuser`)
    - Choose any password (suggestion: `Admin@123` - remember this!)
    - Click through to complete the setup
    - Log in with these credentials

#### Connect to Your Databases

**Connect to PostgreSQL (Your main OMOP database):**

1. Click **"New Connection"** from the top menu
2. Select **"PostgreSQL"** from the list
3. Fill in these exact details:
    - **Host**: `omop-db`
    - **Port**: `5432`
    - **Database**: `postgres`
    - **Username**: `postgres`
    - **Password**: `postgres_pass`
4. Click **"Test Connection"** to make sure it works
5. Click **"Create"**

**Connect to MySQL (For source data and previews):**

1. Click **"New Connection"** again
2. Select **"MySQL"** from the list
3. Fill in these exact details:
    - **Host**: `sqlmesh-db`
    - **Port**: `3306`
    - **Database**: *(leave empty)*
    - **Username**: `root`
    - **Password**: `openmrs`
4. Click **"Create"**

**Important:** Once connected, you'll see two databases:
- `openmrs`: Your source data with 350 patients
- `omop_db`: Preview results from your transformations (available only when you run the pipeline at least once)

---

## Customizing Your Data Transformation

### Understanding SQL Models & SQLMesh

The transformation magic happens using **SQLMesh**, a powerful data transformation framework. Your transformation logic is defined in SQL files located in the `core/models` folder.

**Think of it like this:**
- Raw OpenMRS data (350 patients) goes in → SQLMesh processes your SQL models → Clean OMOP data comes out

**What's Already Done:**
- ✅ **Location** entity mapping (see `core/models/location.sql`)
- ✅ **Person** entity mapping (see `core/models/person.sql`)

**Your Task:**
- 🎯 Map the remaining OMOP entities using the existing models as templates
- Use the same patterns and structure you see in the completed examples

### Making Changes to Your Data Processing

1. **Edit SQL files** in the `core/models` directory using any text editor
2. **Test your changes** using one of the options below


### Run ETL pipelin

Once you're happy with your preview, run the complete pipeline:

```bash
docker compose run --rm core run-pipeline
```

**What this does:**
- Runs the complete ETL process
- Creates final tables in your PostgreSQL OMOP database
- Takes longer but gives you the final production-ready data

---

## Working with Concept Mappings (Advanced - Optional)

**What are concept mappings?** They help translate your local medical codes to standard OMOP codes.

We've provided pre-made mappings, so you can skip this section initially. When you're ready to create custom mappings:

1. Open the **Usagi** tool (included in the project)
2. Import: `concepts/selected_concepts_1to1_updated.csv`
3. Create your mappings
4. Save (don't export!) as `concepts/mapping.csv`

The system will automatically use your new mappings.

---

## Direct Database Access (For Advanced Users)

If you prefer using other database tools, you can connect directly:

**PostgreSQL (Final OMOP Data):**
- **Host**: localhost
- **Port**: 5432
- **Database**: postgres
- **Username**: postgres
- **Password**: postgres_pass


## 🎉 Congratulations!

You now have a working OMOP ETL system! Your OpenMRS data is being transformed into the standard OMOP format, making it ready for research and analysis.
---

### Fancy a User Interface?

```bash
    docker compose run --rm --service-ports core sqlmesh-ui
```

Access the UI at [http://localhost:8000](http://localhost:8000)
   
<img src="/docs/img/sql_mesh.jpeg" alt="SQLMesh UI"> 
-- 

## Fancy a Data Quality Check? (This will cover on upcoming weeks)



### 1. **Run Achilles to generate data summaries** (Check What Achilles does below.)
   ```
   docker compose run achilles
   ``` 
### 2. **Run DQD to perform data quality checks**
This runs the [OHDSI Data Quality Dashboard (DQD)](https://github.com/OHDSI/DataQualityDashboard) on the OMOP database.
   ```bash
    docker compose run --rm dqd run 
   ```
### 3. **View the Data Quality Dashboard**
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

