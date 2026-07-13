# omop-etl-postgresdb

This container is part of the OHDSI  set of Docker containers.
 
A Postgres database in a Docker container pre-configured with OHDSI Atlas/WebAPI application schema tables and loaded with a demo CDM containing synthetic patient data (Eunomia) 
It also contains a very simple demo concept set & cohort definition. See the OHDSI/Eunomia GitHub repo for information about the OHDSI Eunomia sqlite database.

Optional support for Atlas database based security is included with two pre-configured Atlas users:  userid=ohdsi, password=ohdsi and userid=admin, password=admin

This database is intended to be used with the ohdsi Atlas/WebAPI Docker container for Atlas application demo/training and for Atlas/WebAPI software unit testing.


## Start this Postgres database container
```bash
docker compose up -d
```

Database userid: postgres
Default password (can be changed in the docker-compose.yml file): postgres_pass


## Postgres database data management

This container uses a docker volume to manage the Postgres data. It will create a new docker volume called omop-etl-data if it does not already exist.
The Postgres database data will be retained in the docker volume (even if the container is restarted using docker compose down / up -d).

To list the docker volumes on the host server use the below command:
```bash
docker volume ls
```

To reset the postgres database data use the below command. Note this command will permanently delete any data changes made to the demo CDM dataset:
```bash
docker volume rm omop-etl-data
``` 

## postgresql database JDBC connection string - used to connect to this database from a postgresql client

Use localhost as the database host IP address to connect from the local computer where this database container is running (127.0.0.1 is equivalent),
Otherwise use the IP address of the remote server where the container is running
```text
jdbc:postgresql://localhost:5432/postgres?user=postgres&password=postgres_pass
```

## Build the container - only needed to customize the contents of the database
The preferred approach is to just pull the pre-built Docker container image in Docker Hub.
Below is the command to build the container:
```bash
docker compose build
```

## Vendored SQL for offline, deterministic builds
This repository includes pre-generated SQL artifacts under `vendor/` that are used during image build:

- `vendor/cdm/omop_cdm_postgres_ddl.sql`
- `vendor/webapi/results_postgresql.ddl`
- `vendor/webapi/webapi_baseline_V2.2.5.20180212152023_postgresql.sql`

### Regenerating vendored SQL (maintainers)
Prerequisites: git, Java (JRE), and either Maven, curl, or wget.
Set the default versions to use for the SQL (DDL) regeneration script in the Makefile
SQLRENDER_VERSION
WEBAPI_VERSION
CDM_VERSION

- Run the script to regenerate the vendored SQL (DDL) from the required OHDSI WEBAPI and OMOP CDM GitHub versions:
```bash
make regen-webapi-sql
```
- Clean temp files and vendored outputs (keep Maven cache):
```bash
make clean
```
- Purge SqlRender from Maven cache only (forces re-download on next regen):
```bash
make clean-sqlrender
```

If needed, you can point the regen script at a local SqlRender jar:
```bash
SQLRENDER_JAR=/path/to/SqlRender-1.9.2.jar make regen-webapi-sql
```
