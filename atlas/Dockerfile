FROM ohdsi/webapi:latest

USER root

RUN apt-get update && \
    apt-get install -y python3 python3-pip && \
    pip3 install --break-system-packages psycopg2-binary

COPY atlas/init_webapi.py /init_webapi.py
COPY atlas/start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]