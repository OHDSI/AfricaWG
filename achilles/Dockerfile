# syntax=docker/dockerfile:1.4
FROM docker.io/rocker/r-ver:4.3.0@sha256:88e6ef48d74c917fa7449a30307f5254525469eabb053e8392270993daa8f47f

WORKDIR /opt/achilles
ENV DATABASECONNECTOR_JAR_FOLDER="/opt/achilles/drivers"

RUN <<EOF
groupadd -g 10001 achilles
useradd -m -u 10001 -g achilles achilles
mkdir ./drivers
mkdir ./workspace
chown -R achilles .
EOF

# hadolint ignore=DL3008
RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends openjdk-11-jre-headless
apt-get clean
rm -rf /var/lib/apt/lists/*

# The default GitHub Actions runner has 2 vCPUs (https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners)
install2.r --error --ncpus 2 \
  httr \
  remotes \
  rjson \
  littler \
  docopt \
  snow \
  xml2 \
  jsonlite \
  rjava \
  rlang \
  stringr \
  readr \
  dbi \
  urltools \
  bit64 \
  lubridate \
  data.table \
  dplyr \
  fastmap \
  rappdirs \
  fs \
  base64enc \
  digest \
  jquerylib \
  sass \
  htmltools \
  later \
  promises \
  cachem \
  bslib \
  commonmark \
  sourcetools \
  fontawesome \
  xtable \
  httpuv \
  shiny \
  ttr \
  zoo \
  xts \
  quantmod \
  quadprog \
  tseries \
  ParallelLogger \
  SqlRender \
  DatabaseConnector

R CMD javareconf
EOF

# Fallback installation of DatabaseConnector from CRAN in case install2.r didn't install it
RUN R -e "if (!requireNamespace('DatabaseConnector', quietly = TRUE)) install.packages('DatabaseConnector', repos='https://cloud.r-project.org/')"

RUN R <<EOF
library(DatabaseConnector);

downloadJdbcDrivers('postgresql');
downloadJdbcDrivers('redshift');
downloadJdbcDrivers('sql server');
downloadJdbcDrivers('oracle');
downloadJdbcDrivers('spark');
EOF

# this layer is the most likely to change over time so it's useful to keep it separated
# hadolint ignore=DL3059
RUN R -e "remotes::install_github('OHDSI/Achilles@v1.7.2')"

COPY entrypoint.r ./

USER 10001:10001

WORKDIR /opt/achilles/workspace
CMD ["Rscript", "/opt/achilles/entrypoint.r"]
