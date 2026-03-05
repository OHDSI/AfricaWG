from airflow import DAG
from datetime import datetime, timedelta
from airflow.providers.docker.operators.docker import DockerOperator

default_args = {
    'owner': 'you',
    'retries': 0,
    'retry_delay': timedelta(minutes=5)
}


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
        'ACHILLES_RESULTS_SCHEMA': 'results'
    }

    if extra_env:
        base_env.update(extra_env)

    return DockerOperator(
        task_id=task_id,
        image=image,
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode='dbt_default',
        tmp_dir='/opt/airflow/tmp',
        mount_tmp_dir=False,
        command=command,
        environment=base_env
    )

with DAG(
        dag_id='OpenMRS_to_OMOP_ETL',
        default_args=default_args,
        start_date=datetime(2023, 1, 1),
        schedule='@hourly',  # runs every hour
        catchup=False
) as dag:

    clone_openmrs_db = create_core_docker_task("clone_openmrs_db","clone-openmrs-db")
    apply_sqlmesh_plan = create_core_docker_task("apply_sqlmesh_plan", "apply-sqlmesh-plan")
    materialize_mysql_views = create_core_docker_task("materialize_mysql_views", "materialize-mysql-views")
    migrate_to_postresql = create_core_docker_task("migrate_to_postgresql", "migrate-to-postgresql")
    import_omop_concepts = create_core_docker_task("import_omop_concepts", "import-omop-concepts")
    apply_omop_constraints = create_core_docker_task("apply_omop_constraints", "apply-omop-constraints")



    run_achilles = DockerOperator(
        task_id='achilles',
        image='omop-etl-achilles',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode='dbt_default',
        # platform='linux/amd64',
        tmp_dir='/opt/airflow/tmp',
        environment={
            'ACHILLES_DB_URI': 'postgresql://omop-db:5432/omop',
            'ACHILLES_DB_USERNAME': 'omop',
            'ACHILLES_DB_PASSWORD': 'omop',
            'ACHILLES_CDM_SCHEMA': 'public',
            'ACHILLES_VOCAB_SCHEMA': 'public',
            'ACHILLES_RESULTS_SCHEMA': 'public',
            'ACHILLES_CDM_VERSION': '5.4'
        }
    )

clone_openmrs_db >> apply_sqlmesh_plan >> materialize_mysql_views >> migrate_to_postresql >> import_omop_concepts >> apply_omop_constraints >> run_achilles
