from airflow.providers.docker.operators.docker import DockerOperator
from docker.types import Mount
import os

host_root = os.getenv('HOST_PROJECT_ROOT', os.path.dirname(os.path.abspath(__file__)))


def create_core_docker_task(task_id, command, image='omop-etl-core', extra_env=None):
    base_env = {
        'SRC_HOST': 'sqlmesh-db',
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
        'ACHILLES_RESULTS_SCHEMA': 'webapi',
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
