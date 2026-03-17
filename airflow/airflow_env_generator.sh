#!/bin/bash

PROJECT_ROOT=$(pwd)
ENV_FILE="$PROJECT_ROOT/.env-airflow"
DOCKER_GID=$(getent group docker | cut -d: -f3)


echo "AIRFLOW_UID=$(id -u)" > "$ENV_FILE"
echo "DOCKER_GID=$DOCKER_GID" >> "$ENV_FILE"

echo "✅ Created/Updated $ENV_FILE"