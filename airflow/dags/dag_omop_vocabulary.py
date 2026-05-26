from datetime import datetime, timedelta

from airflow.providers.docker.operators.docker import DockerOperator
from airflow.operators.trigger_dagrun import TriggerDagRunOperator
from docker_utils import create_core_docker_task

from airflow import DAG

default_args = {
    'owner': 'you',
    'retries': 1,
    'retry_delay': timedelta(minutes=30)
}

with DAG(
        dag_id='OMOP_Vocabulary_Load',
        default_args=default_args,
        description='Manually triggered DAG to refresh OMOP Vocabularies and Other metadata tables',
        start_date=datetime(2026, 1, 1),
        schedule='@weekly',
        catchup=False,
        tags=['OMOP', 'Vocabulary', 'Setup']
) as dag:
    concept_placeholder_files = create_core_docker_task(
        task_id="generate_concept_placeholder_files",
        command="generate-mapper-placeholder-files"
    )

    sync_openmrs_mappings = create_core_docker_task(
        task_id="sync_openmrs_to_athena_mappings",
        command="sync-omrs-mappings"
    )


    trigger_clinical_migration = TriggerDagRunOperator(
        task_id="trigger_omop_clinical_etl",
        trigger_dag_id="OpenMRS_to_OMOP_Clinical_ETL",
        wait_for_completion=False,
        poke_interval=60,
        reset_dag_run=True,
        failed_states=['failed']
    )

(
        concept_placeholder_files
        >> sync_openmrs_mappings
        >> trigger_clinical_migration
)
