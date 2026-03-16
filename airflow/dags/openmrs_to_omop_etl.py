from airflow import DAG
from datetime import datetime, timedelta
from airflow.providers.docker.operators.docker import DockerOperator
import os
from docker.types import Mount

default_args = {
    'owner': 'you',
    'retries': 0,
    'retry_delay': timedelta(minutes=5)
}

host_root = os.getenv('HOST_PROJECT_ROOT', os.path.dirname(os.path.abspath(__file__)))

def create_core_docker_task(task_id, command, image='omop-etl-core', extra_env=None):
    base_env = {
        'SRC_HOST': 'omrsdb',
        'SRC_PORT': '3306',
        'SRC_USER': 'openmrs',
        'SRC_PASS': 'openmrs',
        'SRC_DB': 'openmrs',
        'SQLMESH_DB_ROOT_PASSWORD': 'openmrs',
        'TARGET_HOST': 'omop-db',
        'TARGET_PORT': '5432',
        'TARGET_USER': 'omop',
        'TARGET_PASS': 'omop',
        'TARGET_DB': 'omop',
        'ACHILLES_VOCAB_SCHEMA': 'vocab',
        'ACHILLES_RESULTS_SCHEMA': 'results',
        'ATLAS_WEB_API_SCHEMA': 'webapi'
    }

    if extra_env:
        base_env.update(extra_env)

    return DockerOperator(
        task_id=task_id,
        image=image,
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode='etl-ohdsi-network',
        command=command,
        environment=base_env,
        mounts=[
            Mount(source=os.path.join(host_root, "concepts"), target="/concepts", type="bind"),
            Mount(source=os.path.join(host_root, "core"), target="/core", type="bind")
        ]
    )

with (DAG(
        dag_id='OpenMRS_to_OMOP_ETL',
        default_args=default_args,
        start_date=datetime(2023, 1, 1),
        schedule='@hourly',  # runs every hour
        catchup=False
) as dag):
    clone_openmrs_db = create_core_docker_task("clone_openmrs_db", "clone-openmrs-db")
    apply_sqlmesh_plan = create_core_docker_task("apply_sqlmesh_plan", "apply-sqlmesh-plan")
    materialize_mysql_views = create_core_docker_task("materialize_mysql_views", "materialize-mysql-views")
    migrate_to_postresql = create_core_docker_task("migrate_to_postgresql", "migrate-to-postgresql")
    import_omop_concepts = create_core_docker_task("import_omop_concepts", "import-omop-concepts")
    apply_omop_constraints = create_core_docker_task("apply_omop_constraints", "apply-omop-constraints")
    populate_cdm_source = create_core_docker_task("populate_cdm_source", "populate-cdm-source")

    run_achilles = DockerOperator(
        task_id='achilles',
        image='omop-etl-achilles',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode='etl-ohdsi-network',
        command="Rscript /opt/achilles/entrypoint.r",
        # platform='linux/amd64',
        tmp_dir='/opt/airflow/tmp',
        mount_tmp_dir=False,
        environment={
            'ACHILLES_DB_URI': 'postgresql://omop-db:5432/omop',
            'ACHILLES_DB_USERNAME': 'omop',
            'ACHILLES_DB_PASSWORD': 'omop',
            'ACHILLES_CDM_SCHEMA': 'public',
            'ACHILLES_VOCAB_SCHEMA': 'public',
            'ACHILLES_RESULTS_SCHEMA': 'results',
            'ACHILLES_CDM_VERSION': '5.4',
            'ACHILLES_NUM_THREADS': '1'
        }
    )

    run_dqd  = DockerOperator(
        task_id='dqd_run',
        image='omop-etl-dqd',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode='etl-ohdsi-network',
        command='Rscript /opt/dqd/run_dqd.R run',
        mounts=[
            Mount(source="jdbc-drivers-data", target="/jdbc", type="volume"),
            Mount(source=os.path.join(host_root, "postprocessing"), target="/postprocessing", type="volume")
        ],
        environment={
            'CDM_CONNECTIONDETAILS_DBMS': "postgresql",
            'CDM_CONNECTIONDETAILS_USER': "omop",
            'CDM_CONNECTIONDETAILS_SERVER': "omop-db/omop",
            'CDM_CONNECTIONDETAILS_PORT': "5432",
            'CDM_CONNECTIONDETAILS_PASSWORD': "omop",
            'CDM_CONNECTIONDETAILS_EXTRA_SETTINGS': "",
            'CDM_VERSION': "5.4",
            'CDM_SOURCE_NAME': "OpenMRS",
            'CDM_DATABASE_SCHEMA': "public",
            'RESULTS_DATABASE_SCHEMA': "results",
            'VOCAB_DATABASE_SCHEMA': "public",
            'DQD_NUM_THREADS': "1",
            'DQD_SQL_ONLY': "FALSE",
            'DQD_SQL_ONLY_UNION_COUNT': "1",
            'DQD_SQL_ONLY_INCREMENTAL_INSERT': "FALSE",
            'DQD_VERBOSE_MODE': "FALSE",
            'DQD_WRITE_TO_TABLE': "TRUE",
            'DQD_WRITE_TABLE_NAME': "dqdashboard_results",
            'DQD_WRITE_TO_CSV': "FALSE",
            'DQD_CSV_FILE': "",
            'DQD_CHECK_LEVELS': "TABLE,FIELD,CONCEPT",
            'DQD_CHECK_NAMES': "",
            'DQD_COHORT_DEFINITION_ID': "",
            'DQD_COHORT_DATABASE_SCHEMA': "public",
            'DQD_COHORT_TABLE_NAME': "cohort",
            'DQD_TABLES_TO_EXCLUDE': "CONCEPT,VOCABULARY,CONCEPT_ANCESTOR,CONCEPT_RELATIONSHIP,CONCEPT_CLASS,CONCEPT_SYNONYM,RELATIONSHIP,DOMAIN",
            'DQD_TABLE_CHECK_THRESHOLD_LOC': "default",
            'DQD_FIELD_CHECK_THRESHOLD_LOC': "default",
            'DQD_CONCEPT_CHECK_THRESHOLD_LOC': "default"
        }
    )

clone_openmrs_db >> apply_sqlmesh_plan >> materialize_mysql_views >> migrate_to_postresql >> import_omop_concepts >> apply_omop_constraints >> populate_cdm_source >> run_achilles >> run_dqd

