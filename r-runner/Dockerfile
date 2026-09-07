# syntax=docker/dockerfile:1.4
FROM docker.io/rocker/r-ver:4.3.3

WORKDIR /app

# System dependencies including Java 11 and essential build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    openjdk-11-jre-headless \
    openjdk-11-jdk-headless \
    libpcre2-dev \
    liblzma-dev \
    libbz2-dev \
    zlib1g-dev \
    libpq-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libuv1-dev \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Set explicit Java environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH=$PATH:$JAVA_HOME/bin
ENV DATABASECONNECTOR_JAR_FOLDER="/app/jdbc"

# Configure R to recognize system Java bindings
RUN R CMD javareconf

# Install essential R packages including shiny for the DQD viewer
RUN Rscript -e "install.packages(c( \
    'remotes', 'httr', 'jsonlite', 'stringr', 'readr', \
    'DBI', 'bit64', 'lubridate', 'data.table', 'dplyr', 'plumber', 'shiny' \
), repos='https://cloud.r-project.org')"

# Install rJava explicitly from source with active javareconf bindings
RUN Rscript -e "install.packages('rJava', repos='https://cloud.r-project.org', type='source')" \
    && Rscript -e "library(rJava); .jinit(); print('rJava loaded successfully!')"

# Install plumber from GitHub to guarantee latest patch support
RUN Rscript -e "remotes::install_github('rstudio/plumber')" \
    && Rscript -e "library(plumber); packageVersion('plumber')"

# Install OHDSI packages and dependencies cleanly (including AresIndexer)
# Install OHDSI packages and dependencies cleanly (Version-Matched)
RUN Rscript -e "suppressMessages(suppressWarnings(remotes::install_github('OHDSI/ParallelLogger', quiet=TRUE)))" \
    && Rscript -e "suppressMessages(suppressWarnings(remotes::install_github('OHDSI/SqlRender', quiet=TRUE)))" \
    && Rscript -e "suppressMessages(suppressWarnings(remotes::install_github('OHDSI/DatabaseConnector', quiet=TRUE)))" \
    && Rscript -e "suppressMessages(suppressWarnings(remotes::install_github('OHDSI/Achilles', quiet=TRUE)))" \
    && Rscript -e "suppressMessages(suppressWarnings(remotes::install_github('OHDSI/DataQualityDashboard', quiet=TRUE)))" \
    && Rscript -e "suppressMessages(suppressWarnings(remotes::install_github('OHDSI/AresIndexer', quiet=TRUE)))"

# Automatically download required PostgreSQL JDBC drivers via DatabaseConnector
RUN R -e "library(DatabaseConnector); downloadJdbcDrivers('postgresql');"

# Create workspace and results directories
RUN mkdir -p /app/jdbc /results /opt/achilles/workspace

# Copy API script
COPY plumber_api.R /app/plumber_api.R

# Expose port
EXPOSE 8001

# Start the Plumber API
CMD ["Rscript", "-e", "library(plumber); pr <- plumber::plumb('/app/plumber_api.R'); pr$run(host='0.0.0.0', port=8001)"]