FROM debian:bookworm

# Install dependencies and pgloader
RUN apt-get update && \
    apt-get install -y \
        curl \
        gnupg \
        lsb-release \
        default-mysql-client \
        postgresql-client \
        pgloader \
        python3 \
        python3-pip \
        libpng-dev \
        libfreetype6-dev \
        pkg-config \
        libpq-dev \
        gcc && \
    rm -rf /var/lib/apt/lists/*


# Install sqlmesh (force system install)
RUN pip install --break-system-packages --no-cache-dir \
    sqlmesh==0.230.0 \
    "pandas<3.0" \
    matplotlib \
    pymysql \
    psycopg2-binary \
    requests \
    sqlalchemy \
    "sqlmesh[web]"

ENV SQLMESH_LOG_LEVEL=ERROR

# set workdir
WORKDIR /core


COPY models models
COPY config.yaml .
COPY entrypoint.sh .
COPY export_concepts.py .
COPY placeholder_files_generator.py .
COPY automated_athena_mappings.py .
COPY automated_mapping_summary.py .


RUN chmod +x /core/entrypoint.sh

ENTRYPOINT ["/core/entrypoint.sh"]
