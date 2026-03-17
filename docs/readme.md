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
