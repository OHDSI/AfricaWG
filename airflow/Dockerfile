FROM apache/airflow:3.1.8


USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN echo "airflow ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER ${AIRFLOW_UID}

WORKDIR /opt/airflow