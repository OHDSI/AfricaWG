# OMOP ETL Deep Dive - Getting Started Guide

This project helps you transform healthcare data from OpenMRS into the OMOP Common Data Model format using **SQLMesh** as the transformation engine. Don't worry if you're new to this - we'll guide you through each step!

## 📹 Session Recording

This entire setup and workflow was covered in our previous call. You can watch the full recording here:
**[OHDSI Africa Chapter - OMOP ETL Deep Dive Session](https://ohdsiorg.sharepoint.com/:v:/s/Chapter-Africa/EaOu_rXBPoJDiq_BGAMUfPUBIm-vd661Xv_Uy6EYV000dg?e=i2sUWd)**

## Your Goal

We've already mapped two entities during the call (**Location** and **Person**) - you can find these examples in the `core/models` folder. Your task is to **map the remaining OMOP entities** using these as reference templates.

**Dataset Info:** You'll be working with a sample OpenMRS database containing **250 patients** to practice your transformations.

## What You'll Need Before Starting

- **Docker Desktop** installed on your computer ([Download here](https://www.docker.com/products/docker-desktop/))
- **Basic command line knowledge** (we'll show you the exact commands to type)
- About **30 minutes** for the initial setup


#### Installing Docker

<details>
<summary>mac OS</summary>


1. **Manual Installation:**
    - Download Docker Desktop from [https://www.docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop)
    - Install and launch Docker Desktop
    - Ensure Docker is running (you should see the Docker icon in your menu bar)
2. Or ** Using Homebrew:**
   ```bash
   brew install --cask docker
   ```
   Then launch Docker Desktop from Applications.
</details>

<details>
<summary>Windows</summary>

1. Download Docker Desktop from [https://www.docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop)
2. Install and launch Docker Desktop
3. Ensure WSL 2 is enabled if prompted
</details>

<details>
<summary>Linux (Ubuntu/Debian)</summary>


```bash
# Update package index
sudo apt-get update

# Install prerequisites
sudo apt-get install apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add your user to docker group (optional, to avoid sudo)
sudo usermod -aG docker $USER
```

</details>


## Quick Start (3 Simple Steps)

### Step 1: Get the Project Files

**Option A: Download ZIP file (Recommended for beginners)**
1. Visit: https://github.com/OHDSI/AfricaWG.git
2. Download and extract the ZIP file to a folder on your computer
3. Open your terminal/command prompt and navigate to that folder

**Option B: Use Git (If you have Git installed)**

Make sure you have LFS installed. Check [Setting Up git LFS](#setting-up-git-lfs)
```bash
git clone https://github.com/OHDSI/AfricaWG.git
cd omop-etl-deep-dive
```

### Step 2: Build the Project

This step prepares all the necessary software components. It may take 5-10 minutes the first time.

```bash
docker compose --profile manual build
```

**What this does:** Downloads and sets up all the databases and tools you'll need.

### Step 3: Start Everything

```bash
docker compose up
```

**What this does:** Starts all the services including databases and web interfaces.

**✅ Success indicator:** You'll see messages saying services are ready. The process is complete when you stop seeing new log messages.

---

## What's Now Available?

After running the setup, you'll have access to:

- **CloudBeaver** (Database viewer): http://localhost:8978
- **OMOP PostgreSQL Database**: Available at localhost:5433
- **MySQL Database**: Contains OpenMRS DB and available internally for quick previews

---

## Working with Your Data

### Understanding the Database Setup

You now have three main databases:
- **PostgreSQL** (omop-db): Your final OMOP-formatted data lives here
- **MySQL** (sqlmesh-db): Contains two databases:
    - `openmrs`: Your source OpenMRS dataset with 250 patients
    - `omop_db`: Used for quick previews and intermediate processing

### Viewing Your Data with CloudBeaver

CloudBeaver is a web-based tool that lets you explore your databases without needing to install additional software.

#### First Time Setup (Only do this once)

1. **Open CloudBeaver**: Go to http://localhost:8978 in your web browser

2. **Create Your Admin Account** (First time only):
    - You'll see a Setup Wizard
    - Choose any username (suggestion: `admin`)
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
    - **Database**: `omop`
    - **Username**: `omop`
    - **Password**: `omop`
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
- `openmrs`: Your source data with 250 patients
- `omop_db`: Preview results from your transformations (available only when you run the pipeline at least once)

---

## Customizing Your Data Transformation

### Understanding SQL Models & SQLMesh

The transformation magic happens using **SQLMesh**, a powerful data transformation framework. Your transformation logic is defined in SQL files located in the `core/models` folder.

**Think of it like this:**
- Raw OpenMRS data (250 patients) goes in → SQLMesh processes your SQL models → Clean OMOP data comes out

**What's Already Done:**
- ✅ **Location** entity mapping (see `core/models/location.sql`)
- ✅ **Person** entity mapping (see `core/models/person.sql`)

**Your Task:**
- 🎯 Map the remaining OMOP entities using the existing models as templates
- Use the same patterns and structure you see in the completed examples

### Making Changes to Your Data Processing

1. **Edit SQL files** in the `core/models` directory using any text editor
2. **Test your changes** using one of the options below

### Option 1: Quick Preview (Recommended for testing)

Perfect for checking if your changes work before running the full process:

```bash
docker compose run --rm core apply-sqlmesh-plan
```

**What this does:**
- Runs your transformations quickly in MySQL
- Creates preview tables you can check in CloudBeaver
- Look for results under the MySQL connection → `omop_db` database
- Results appear as "views" (think of them as virtual tables)

### Option 2: Full Production Run

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
- **Port**: 5433
- **Database**: omop
- **Username**: omop
- **Password**: omop


## 🎉 Congratulations!

You now have a working OMOP ETL system! Your OpenMRS data is being transformed into the standard OMOP format, making it ready for research and analysis.

**Next steps:**
- Explore your data using CloudBeaver
- Try making small changes to the SQL models
- Run the preview command to see your changes in action

**Need help?** Check the project's GitHub issues page or documentation for more advanced topics.




Once your work is done, you can stop the services with:

```bash
docker compose stop
```

---

## Troubleshooting Common Issues

**"Docker command not found"**
- Make sure Docker Desktop is installed and running

**"Port already in use"**

* Option 1: Stop applications using the conflicting ports
* Option 2: Change the ports in your docker-compose.yml file
*
* To change ports, find the ports: sections and update the left side (your computer's port):
```yaml
* ports:
- "change_this_port:8978"  # CloudBeaver
```
Example: If port 8978 is busy, change it to 8979:
```yaml
ports:
- "8979:8978"  # Now access CloudBeaver at localhost:8979
```
Note: Only change the number before the colon. The number after the colon must stay the same.**"Connection refused" in CloudBeaver**

**"Connection refused" in CloudBeaver**
- Wait a few minutes after running `docker compose up`
- Make sure all services are fully started (check the logs)

**Changes not showing up**
- Make sure you ran either the preview or full pipeline command after making changes
- Check that your SQL syntax is correct

**You see pointer files instead of actual data when opening a large file (e.g., `CONCEPT.csv`)**
it means Git LFS is not set up correctly. Run:

```sh
git lfs pull
```

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





##### Setting Up Git LFS
<summary>Setting Up Git LFS for This Repository</summary>

<details>

### Setting Up Git LFS for This Repository

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



---


For more information, refer to the [Git LFS documentation](https://git-lfs.github.com/).
</details>
