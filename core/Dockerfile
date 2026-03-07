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
RUN pip install --break-system-packages sqlmesh==0.190.0
RUN pip install --break-system-packages pymysql
RUN pip install --break-system-packages sqlalchemy
RUN pip install --break-system-packages pandas

# set workdir
WORKDIR /core

COPY seed seed
COPY omop-ddl omop-ddl
COPY models models
COPY config.yaml .
COPY entrypoint.sh .


RUN chmod +x /core/entrypoint.sh

ENTRYPOINT ["/core/entrypoint.sh"]
