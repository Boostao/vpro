# syntax=docker/dockerfile:1.7

# VPro 2.0 Read-Only Web Server & Snapshot Verifier Container (Linux amd64)
# Build context: repository root (.)
#   Default (with read-only R sidecar: climr/aSMR, vegclust, Quarto guides):
#     docker build --platform linux/amd64 -f deploy/vpro-web/Dockerfile -t vpro-web:dev .
#   Go-only lean runtime (~55 MB, no R/Quarto):
#     docker build --platform linux/amd64 --build-arg INCLUDE_R=false -f deploy/vpro-web/Dockerfile -t vpro-web:lean .

ARG INCLUDE_R=true
ARG QUARTO_VERSION=1.6.42

# ------------------------------------------------------------------------------
# Stage 1: Frontend Web Bundle (Svelte 5 + TypeScript + Web RPC Map Check)
# ------------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM node:24-bookworm-slim AS frontend-builder

WORKDIR /src

# Install frontend dependencies first for optimal build-cache reuse
COPY app/frontend/package.json app/frontend/package-lock.json app/frontend/.npmrc ./app/frontend/
RUN cd /src/app/frontend && npm ci

# Copy only the source inputs needed for RPC map verification and Vite web build
COPY scripts/generate-web-rpc-map.mjs ./scripts/generate-web-rpc-map.mjs
COPY app/resources/*.json ./app/resources/
COPY app/frontend/index.html app/frontend/tsconfig.json app/frontend/svelte.config.js ./app/frontend/
COPY app/frontend/vite.config.ts app/frontend/vite.web.config.ts ./app/frontend/
COPY app/frontend/bindings ./app/frontend/bindings
COPY app/frontend/public ./app/frontend/public
COPY app/frontend/src ./app/frontend/src

RUN node /src/scripts/generate-web-rpc-map.mjs --check \
    && cd /src/app/frontend \
    && npm run build:web \
    && test -s /src/app/frontend/dist-web/index.html

# ------------------------------------------------------------------------------
# Stage 2: Headless Go Builder (CGO for go-sqlite3 only; ZERO GTK/WebKit/Wails)
# ------------------------------------------------------------------------------
FROM golang:1.27-bookworm AS go-builder

ENV CGO_ENABLED=1 \
    GOOS=linux \
    GOARCH=amd64 \
    GOTOOLCHAIN=go1.27.4+auto

WORKDIR /src/app

COPY app/go.mod app/go.sum ./
RUN go mod download

COPY app/cmd ./cmd
COPY app/internal ./internal
COPY app/resources ./resources

# Embed the freshly built web SPA bundle into cmd/vpro-web/static/
RUN rm -rf /src/app/cmd/vpro-web/static
COPY --from=frontend-builder /src/app/frontend/dist-web/ /src/app/cmd/vpro-web/static/

RUN mkdir -p /out \
    && go build -tags vpro_headless -trimpath -ldflags="-s -w" -o /out/vpro-web ./cmd/vpro-web \
    && go build -tags vpro_headless -trimpath -ldflags="-s -w" -o /out/vpro-snapshot ./cmd/vpro-snapshot

# ------------------------------------------------------------------------------
# Stage 3 (optional): R SDK & Ecology Package Builder (skipped if INCLUDE_R=false)
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim AS r-builder

ARG DEBIAN_FRONTEND=noninteractive

# Install R >= 4.4.0 from official CRAN Debian bookworm-cran40 repository + build headers
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL --retry 3 --retry-delay 2 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xBA4EE5DE858FFFA7CFD8563908FC7B745769E9E4" \
        | gpg --dearmor -o /etc/apt/keyrings/cran-debian.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/cran-debian.gpg] https://cloud.r-project.org/bin/linux/debian bookworm-cran40/" \
        > /etc/apt/sources.list.d/cran-debian.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        r-base-core \
        r-base-dev \
        build-essential \
        gfortran \
        pkg-config \
        cmake \
        git \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libsqlite3-dev \
        libgdal-dev \
        libgeos-dev \
        libproj-dev \
        libudunits2-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# Install CRAN dependencies using Posit Public Package Manager Bookworm precompiled binaries
RUN Rscript -e ' \
    options( \
        repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/bookworm/latest"), \
        HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])), \
        Ncpus = max(1L, parallel::detectCores()) \
    ); \
    pkgs <- c( \
        "cli", "data.table", "DBI", "jsonlite", "rlang", "RSQLite", "tibble", "yaml", \
        "vegan", "vegclust", "cluster", "indicspecies", \
        "ggplot2", "knitr", "rmarkdown", "quarto", \
        "sf", "terra", "Matrix", "remotes", "withr" \
    ); \
    install.packages(pkgs, lib = "/usr/local/lib/R/site-library"); \
    missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1L), quietly = TRUE)]; \
    if (length(missing) > 0L) stop("Missing CRAN packages: ", paste(missing, collapse = ", ")) \
'

# Install bcgov/climr (using optional BuildKit github_pat secret in CI to avoid rate limits)
RUN --mount=type=secret,id=github_pat \
    if [ -s /run/secrets/github_pat ]; then export GITHUB_PAT="$(cat /run/secrets/github_pat)"; fi \
    && Rscript -e ' \
        options( \
            repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/bookworm/latest"), \
            HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])), \
            Ncpus = max(1L, parallel::detectCores()) \
        ); \
        remotes::install_github("bcgov/climr", lib = "/usr/local/lib/R/site-library", dependencies = TRUE, upgrade = "never"); \
        stopifnot(requireNamespace("climr", quietly = TRUE)) \
    '

# Install local headless vpro R companion SDK
COPY r/DESCRIPTION r/NAMESPACE r/.Rbuildignore /tmp/vpro-r/
COPY r/R /tmp/vpro-r/R
COPY r/inst /tmp/vpro-r/inst
COPY r/man /tmp/vpro-r/man
RUN R CMD INSTALL --no-multiarch --library=/usr/local/lib/R/site-library /tmp/vpro-r \
    && rm -rf /tmp/vpro-r \
    && Rscript -e 'stopifnot( \
        requireNamespace("vpro", quietly = TRUE), \
        requireNamespace("climr", quietly = TRUE), \
        requireNamespace("vegclust", quietly = TRUE), \
        requireNamespace("vegan", quietly = TRUE), \
        requireNamespace("ggplot2", quietly = TRUE), \
        requireNamespace("knitr", quietly = TRUE), \
        requireNamespace("rmarkdown", quietly = TRUE) \
    )'

# ------------------------------------------------------------------------------
# Stage 4a: Runtime Base WITH Lean R + vpro SDK + Pinned Quarto CLI
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime-r-true

ARG DEBIAN_FRONTEND=noninteractive
ARG QUARTO_VERSION=1.6.42

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL --retry 3 --retry-delay 2 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xBA4EE5DE858FFFA7CFD8563908FC7B745769E9E4" \
        | gpg --dearmor -o /etc/apt/keyrings/cran-debian.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/cran-debian.gpg] https://cloud.r-project.org/bin/linux/debian bookworm-cran40/" \
        > /etc/apt/sources.list.d/cran-debian.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        r-base-core \
        libcurl4 \
        libssl3 \
        libxml2 \
        libsqlite3-0 \
        libgdal32 \
        libgeos-c1v5 \
        libproj25 \
        libudunits2-0 \
        libfontconfig1 \
        libharfbuzz0b \
        libfribidi0 \
        libfreetype6 \
        libpng16-16 \
        libtiff6 \
        libjpeg62-turbo \
        libgomp1 \
        libgfortran5 \
    && curl -fsSL "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.deb" \
        -o /tmp/quarto.deb \
    && dpkg -i /tmp/quarto.deb \
    && rm -f /tmp/quarto.deb \
    && apt-get purge -y --auto-remove gnupg \
    && rm -rf /var/lib/apt/lists/* /tmp/*

COPY --from=r-builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

ENV R_LIBS_SITE=/usr/local/lib/R/site-library \
    VPRO_RSCRIPT_PATH=/usr/bin/Rscript \
    VPRO_QUARTO_PATH=/usr/local/bin/quarto

RUN quarto --version \
    && Rscript -e 'stopifnot(requireNamespace("vpro", quietly = TRUE), requireNamespace("vegclust", quietly = TRUE))'

# ------------------------------------------------------------------------------
# Stage 4b: Lean Go-Only Runtime Base (~55 MB total image)
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime-r-false

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

ENV VPRO_RSCRIPT_PATH=none \
    VPRO_QUARTO_PATH=none

# ------------------------------------------------------------------------------
# Stage 5: Final Hardened Non-Root Runtime Image
# ------------------------------------------------------------------------------
FROM runtime-r-${INCLUDE_R} AS runtime

LABEL org.opencontainers.image.title="VPro 2.0 Read-Only Web Server" \
      org.opencontainers.image.description="Read-only BECMaster / VPro 2.0 web viewer, snapshot verifier, and optional R/Quarto analytical sidecar" \
      org.opencontainers.image.source="https://github.com/Boostao/vpro" \
      org.opencontainers.image.licenses="Apache-2.0"

RUN groupadd --gid 10001 --system vpro \
    && useradd --uid 10001 --gid 10001 --system --home-dir /tmp/vpro-exports/home --shell /usr/sbin/nologin vpro \
    && install -d -o 10001 -g 10001 -m 0755 /data /srv/vpro/data /pmtiles /pictures /tmp/vpro-exports

COPY --from=go-builder --chmod=0755 /out/vpro-web /usr/local/bin/vpro-web
COPY --from=go-builder --chmod=0755 /out/vpro-snapshot /usr/local/bin/vpro-snapshot

ENV TMPDIR=/tmp/vpro-exports \
    HOME=/tmp/vpro-exports/home \
    XDG_CACHE_HOME=/tmp/vpro-exports/cache \
    XDG_CONFIG_HOME=/tmp/vpro-exports/config \
    XDG_DATA_HOME=/tmp/vpro-exports/data \
    DENO_DIR=/tmp/vpro-exports/deno \
    R_USER_CACHE_DIR=/tmp/vpro-exports/r-cache \
    VPRO_WEB_DATA_DIR=/data \
    VPRO_WEB_PMTILES_DIR=/pmtiles \
    VPRO_WEB_PICTURES_DIR=/pictures \
    VPRO_WEB_EXPORT_DIR=/tmp/vpro-exports \
    VPRO_WEB_LISTEN_ADDR=:8080 \
    VPRO_WEB_INTERNAL_ADDR=:9090

USER 10001:10001

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=15s --retries=3 \
    CMD ["curl", "-fsS", "http://127.0.0.1:8080/healthz"]

ENTRYPOINT ["/usr/local/bin/vpro-web"]
