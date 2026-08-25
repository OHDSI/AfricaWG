# OHDSI OMOP ETL Deep Dive Database

This repository contains the configuration, SQL scripts, and Docker definitions required to build and run a **pre-populated PostgreSQL database** for OHDSI OMOP Common Data Model (CDM) deep-dive exercises.

The database includes the **OMOP CDM structure, standard vocabularies, and WebAPI/Atlas configuration**, providing a ready-to-use environment for ETL development, vocabulary exploration, concept mapping, and OMOP training.

## Architecture & Features

- **Multi-Stage Docker Build**  
  Uses a multi-stage Docker build to initialize and populate the PostgreSQL data directory during image creation. This leverages the PostgreSQL `docker-entrypoint.sh` initialization mechanism so the final container starts with the database already populated.

- **Pre-Populated OMOP Database**  
  Includes OMOP CDM schemas, tables, standard vocabularies, constraints, indexes, and supporting WebAPI configuration.

- **Flexible Authentication**  
  Supports standard password authentication as well as Docker secret-based password configuration through the `PASSWORD_METHOD` build argument.

- **Automated Database Initialization**  
  SQL scripts are executed sequentially to create schemas, load vocabularies, configure primary keys and indexes, apply constraints, and configure WebAPI security.

- **Persistent Storage**  
  A Docker named volume is used to persist the PostgreSQL data directory across container restarts.

## Prerequisites

Before starting, ensure you have:

- **Docker** v20.10 or later
- **Docker Compose** v2.20 or later
- At least **2 GB RAM** allocated to Docker
- At least **2 CPU cores** allocated to Docker
- Sufficient disk space for the OMOP vocabulary data and PostgreSQL database

## Project Structure

```text
.
├── Dockerfile
├── docker-compose.yml
├── Makefile
│
├── vocabularies/
│   └── # OMOP vocabulary CSV/ZIP files
│
├── 010_create_cdm_schemas.sql
├── omop_cdm_postgres_ddl.sql
├── 040_load_cdm_vocabularies.sql
├── 045_..._primary_keys.sql
├── 050_..._indexes.sql
├── 060_..._constraints.sql
└── 080_..._security_schema.sql
```

### Key Files

| File | Purpose |
|---|---|
| `Dockerfile` | Multi-stage Docker build used to initialize and pre-populate PostgreSQL |
| `docker-compose.yml` | Defines the database service, ports, volumes, and environment variables |
| `Makefile` | Provides helper commands for common database operations |
| `vocabularies/` | Contains OMOP vocabulary files used to populate the database |
| `010_create_cdm_schemas.sql` | Creates the OMOP CDM and supporting schemas |
| `omop_cdm_postgres_ddl.sql` | Creates the OMOP CDM tables |
| `040_load_cdm_vocabularies.sql` | Loads OMOP vocabulary data |
| `045_..._primary_keys.sql` | Creates primary key constraints |
| `050_..._indexes.sql` | Creates database indexes |
| `060_..._constraints.sql` | Creates foreign keys and integrity constraints |
| `080_..._security_schema.sql` | Configures WebAPI security and permissions |

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd <repository-directory>
```

### 2. Build and Start the Database

Build the image and start the database using Docker Compose:

```bash
docker compose up --build -d
```

The first build may take some time because the PostgreSQL data directory and OMOP vocabularies are populated during image creation.

### 3. Check Container Status

Verify that the database container is running:

```bash
docker compose ps
```

### 4. Verify PostgreSQL Readiness

You can check whether PostgreSQL is ready to accept connections:

```bash
docker exec -it omop-etl-deepdive-db pg_isready -U postgres
```

A successful response should indicate that PostgreSQL is accepting connections.

## Database Configuration

The default configuration exposes PostgreSQL on port `5432`.

| Setting | Default |
|---|---|
| Host Port | `5432` |
| PostgreSQL User | `postgres` |
| PostgreSQL Password | `postgres_pass` |
| PostgreSQL Data Directory | `/var/lib/postgresql/data` |

> **Security note:** The default password is intended for local development and training environments. For production or shared environments, use a strong password or Docker secrets.

## Volumes

The database uses a Docker named volume:

```text
omop-etl-data
```

which is mounted to:

```text
/var/lib/postgresql/data
```

This ensures that database data remains available when the container is restarted or recreated.

To inspect the volume:

```bash
docker volume inspect omop-etl-data
```

To list Docker volumes:

```bash
docker volume ls
```

> **Warning:** Removing the named volume will permanently remove the persisted PostgreSQL database data.

## Connecting to PostgreSQL

Once the container is running, PostgreSQL can be accessed from the host using:

```text
Host: localhost
Port: 5432
Username: postgres
Password: postgres_pass
```

For example, using `psql`:

```bash
psql -h localhost -p 5432 -U postgres
```

You can also connect using database clients such as **DBeaver**, **pgAdmin**, or other PostgreSQL-compatible tools.

## Connecting from Another Docker Container

When connecting from another service within the same Docker Compose network, use the PostgreSQL service name defined in `docker-compose.yml` rather than `localhost`.

For example:

```text
Host: <postgres-service-name>
Port: 5432
Username: postgres
Password: postgres_pass
```

## Advanced Build Options

### Docker Secret Password Configuration

The default build uses the password configuration defined by the Docker Compose environment.

For environments where you do not want to rely on a plain-text password configuration, the image can be built using the secret-based password method:

```bash
docker build \
  --build-arg PASSWORD_METHOD=use-password-secret \
  .
```

The exact secret configuration should match the implementation provided in the repository's `Dockerfile` and Compose configuration.

## Rebuilding the Database

If the SQL scripts or vocabulary files change, rebuild the image:

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

If you also want to recreate the database from scratch, remove the existing named volume:

```bash
docker compose down -v
docker compose up --build -d
```

> **Warning:** `docker compose down -v` removes the database volume and therefore deletes the persisted database contents.

## Troubleshooting

### PostgreSQL Is Not Ready

Check the container logs:

```bash
docker compose logs -f
```

You can also check PostgreSQL directly:

```bash
docker exec -it omop-etl-deepdive-db pg_isready -U postgres
```

### Container Keeps Restarting

Inspect the service logs:

```bash
docker compose logs omop-etl-deepdive-db
```

Look for errors related to:

- PostgreSQL initialization
- Vocabulary files
- SQL syntax
- File permissions
- Database constraints
- Disk space
- Authentication

### Database Contains Old Data

If you changed initialization scripts but the existing database volume is still being reused, PostgreSQL may not rerun the initialization scripts.

Recreate the database volume:

```bash
docker compose down -v
docker compose up --build -d
```

### Build Takes a Long Time

The initial build can take considerably longer than subsequent container starts because the build process populates the PostgreSQL database and loads the OMOP vocabularies.

Once the image has been built successfully, starting the container should be significantly faster.

## Intended Use

This database environment is intended primarily for:

- OMOP CDM training
- ETL development
- Vocabulary exploration
- Concept mapping exercises
- OHDSI deep-dive sessions
- WebAPI/Atlas experimentation
- Testing OMOP-related tools and integrations

It provides a reproducible environment in which participants can work with a pre-configured OMOP database without having to manually install and populate the CDM and vocabulary tables.

## Data and Vocabulary Requirements

OMOP vocabulary files can be large and may be subject to licensing and distribution restrictions. Ensure that the vocabulary files placed in the `vocabularies/` directory are obtained and distributed in accordance with their respective licensing requirements.

The repository should generally contain the scripts and configuration required to load the vocabularies rather than redistributing vocabulary data when redistribution is not permitted.

## Maintenance

When updating the database:

1. Update the relevant SQL scripts.
2. Update or replace vocabulary files as required.
3. Rebuild the Docker image.
4. Recreate the database volume when initialization scripts need to run from scratch.
5. Verify database health.
6. Verify the OMOP schemas, vocabulary tables, indexes, and constraints.

## License

Add the applicable project license here.

If the repository includes third-party OHDSI or OMOP components, ensure that their respective licenses and attribution requirements are also respected.