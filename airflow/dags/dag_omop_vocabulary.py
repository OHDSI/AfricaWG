from datetime import datetime, timedelta

from airflow.providers.docker.operators.docker import DockerOperator
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
        schedule=None,
        catchup=False,
        tags=['OMOP', 'Vocabulary', 'Setup']
) as dag:
    import_concepts = create_core_docker_task(
        task_id="import_omop_concepts",
        command="import-omop-concepts"
    )

    apply_constraints = create_core_docker_task(
        task_id="apply_omop_constraints",
        command="apply-omop-constraints"
    )

    update_cdm_metadata = create_core_docker_task(
        task_id="update_cdm_source_metadata",
        command="populate-cdm-source"
    )

import_concepts >> apply_constraints >> update_cdm_metadata
