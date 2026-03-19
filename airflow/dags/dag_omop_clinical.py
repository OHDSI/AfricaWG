from datetime import datetime, timedelta

from airflow.providers.common.sql.sensors.sql import SqlSensor
from airflow.providers.docker.operators.docker import DockerOperator
from docker.types import Mount
from docker_utils import create_core_docker_task

from airflow import DAG

default_args = {
    'owner': 'you',
    'retries': 1,
    'retry_delay': timedelta(minutes=10)
}

with DAG(
        dag_id='OpenMRS_to_OMOP_Clinical_ETL',
        default_args=default_args,
        start_date=datetime(2026, 1, 1),
        schedule='0 */8 * * *',  # Every 8 hours
        catchup=False,
        tags=['OMOP', 'Clinical', 'Daily']
) as dag:
    apply_sqlmesh_plan = create_core_docker_task("apply_sqlmesh_plan", "apply-sqlmesh-plan")
    materialize_mysql_views = create_core_docker_task("materialize_mysql_views", "materialize-mysql-views")
    migrate_to_postgresql = create_core_docker_task("migrate_to_postgresql", "migrate-to-postgresql")

    wait_for_vocab = SqlSensor(
        task_id='wait_for_vocabulary',
        conn_id='omop_db_postgres',
        sql="SELECT COUNT(*) FROM public.vocabulary WHERE vocabulary_id = 'None';",
        mode='reschedule',  # Reschedule releases the worker slot while waiting
        poke_interval=60,
        timeout=1200  # 20 minute timeout
    )

    populate_cdm_source = create_core_docker_task("populate_cdm_source", "populate-cdm-source")

    run_achilles = DockerOperator(
        task_id='achilles',
        image='omop-etl-achilles',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode='etl-ohdsi-network',
        command="Rscript /opt/achilles/entrypoint.r",
        environment={
            'ACHILLES_DB_URI': 'postgresql://omop-db:5432/omop',
            'ACHILLES_DB_USERNAME': 'omop',
            'ACHILLES_DB_PASSWORD': 'omop',
            'ACHILLES_CDM_SCHEMA': 'public',
            'ACHILLES_VOCAB_SCHEMA': 'public',
            'ACHILLES_RESULTS_SCHEMA': 'webapi',
            'ACHILLES_CDM_VERSION': '5.4',
            'ACHILLES_NUM_THREADS': '1'
        }
    )

    run_dqd = DockerOperator(
        task_id='dqd_run',
        image='omop-etl-dqd',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode='etl-ohdsi-network',
        command='Rscript /opt/dqd/run_dqd.R run',
        mounts=[
            Mount(source="jdbc-drivers-data", target="/jdbc", type="volume"),
            Mount(source="cdm-postprocessing-data", target="/postprocessing", type="volume")
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
            'RESULTS_DATABASE_SCHEMA': "webapi",
            'VOCAB_DATABASE_SCHEMA': "public",
            'DQD_NUM_THREADS': "1",
            'DQD_SQL_ONLY': "FALSE",
            'DQD_SQL_ONLY_UNION_COUNT': "1",
            'DQD_SQL_ONLY_INCREMENTAL_INSERT': "FALSE",
            'DQD_VERBOSE_MODE': "TRUE",
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

(
        apply_sqlmesh_plan
        >> materialize_mysql_views
        >> migrate_to_postgresql
        >> wait_for_vocab
        >> populate_cdm_source
        >> run_achilles
        >> run_dqd
)
