# Use rocker/shiny:4.3 as the base image for stability
FROM rocker/shiny:4.3

# Install system dependencies required for R packages and spatial operations
# libcurl: for network operations
# libssl: for encryption/HTTPS
# libxml2: for XML parsing
# libpq: for PostgreSQL connectivity (required by DuckDB postgres extension)
# libgdal, libproj, libgeos, libudunits2: for sf/leaflet spatial packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libpq-dev \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    libudunits2-dev \
    pandoc \
    zlib1g-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Quarto for report generation
# Quarto is used for generating the PDF/HTML reports from .qmd templates
RUN curl -LO https://github.com/quarto-dev/quarto-cli/releases/download/v1.3.450/quarto-1.3.450-linux-amd64.deb \
    && dpkg -i quarto-1.3.450-linux-amd64.deb \
    && rm quarto-1.3.450-linux-amd64.deb

# Set working directory in the container
WORKDIR /srv/shiny-server

# Copy renv.lock to restore the R environment
# We don't copy the whole renv/ directory to keep the image clean
COPY renv.lock ./

# Install renv and restore packages
# This step is done before copying the app to leverage Docker layer caching
# Setting RENV_PATHS_LIBRARY helps stay consistent with some environments
ENV RENV_PATHS_LIBRARY renv/library
RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')" \
    && R -e "renv::restore()"

# Copy the application source code
COPY . .

# Ensure the app files are owned by the shiny user for security
RUN chown -R shiny:shiny /srv/shiny-server

# Expose port 3838 for the Shiny app
EXPOSE 3838

# Change to the shiny user
USER shiny

# Start the Shiny app on container launch
# Using host 0.0.0.0 to listen on all interfaces within the container
CMD ["R", "-e", "shiny::runApp('/srv/shiny-server', host = '0.0.0.0', port = 3838)"]
