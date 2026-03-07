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
        python3-pip && \
    rm -rf /var/lib/apt/lists/*


# Install sqlmesh (force system install)
RUN pip install --break-system-packages \
    sqlmesh==0.230.0 \
    "pandas<3.0" \
    pymysql \
    sqlalchemy
# set workdir
WORKDIR /core

COPY seed seed
COPY omop-ddl omop-ddl
COPY models models
COPY config.yaml .
COPY entrypoint.sh .


RUN chmod +x /core/entrypoint.sh

ENTRYPOINT ["/core/entrypoint.sh"]
