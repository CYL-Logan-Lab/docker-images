# Reproducible analysis environment for CYL-Logan-Lab/Logan-T2D-Genomic.
# The downstream Docker Compose project name is t2d-meta-lipid.
#
# Reproducibility layers:
#   1. R 4.5.2 base image is pinned by OCI digest.
#   2. CRAN packages come from the 2026-08-06 Posit snapshot.
#   3. Every package used directly by R0 or the approved R7P API workflow has
#      an exact version assertion.
# The full resolved R and Debian package inventories are baked into /opt.
FROM rocker/r-ver@sha256:fd4ccdd3a4a6f7ef805e2daeee2a0fe3bf126bc231f36351223baecf5a595a4c

LABEL org.opencontainers.image.source="https://github.com/CYL-Logan-Lab/docker-images"
LABEL org.opencontainers.image.description="Docker-only R0 and R7P analysis environment for Logan-T2D-Genomic"
LABEL org.opencontainers.image.base.name="rocker/r-ver@sha256:fd4ccdd3a4a6f7ef805e2daeee2a0fe3bf126bc231f36351223baecf5a595a4c"

ARG APP_UID=1000
ARG APP_GID=1000
ARG COLOC_SOURCE_COMMIT=50fe5291fea7f8ab49823bd86747385d6e56870f
ARG CURL_DEB_VERSION=8.5.0-2ubuntu10.11

ENV LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    TZ=UTC \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    VECLIB_MAXIMUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    R0_CRAN_REPO=https://packagemanager.posit.co/cran/__linux__/noble/2026-08-06 \
    R0_COLOC_SOURCE_COMMIT=${COLOC_SOURCE_COMMIT}

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      "curl=${CURL_DEB_VERSION}" \
      "libcurl4t64=${CURL_DEB_VERSION}" \
 && rm -rf /var/lib/apt/lists/*

COPY install-Rpkgs.R /opt/install-Rpkgs.R

RUN Rscript --vanilla /opt/install-Rpkgs.R \
 && dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort > /opt/system-manifest.tsv \
 && { \
      printf 'base_image\t%s\n' 'rocker/r-ver@sha256:fd4ccdd3a4a6f7ef805e2daeee2a0fe3bf126bc231f36351223baecf5a595a4c'; \
      printf 'r_version\t%s\n' '4.5.2'; \
      printf 'python\t%s\n' 'PYTHON_NOT_INSTALLED'; \
      printf 'cran_snapshot\t%s\n' "${R0_CRAN_REPO}"; \
      printf 'coloc_version\t%s\n' '6.0.1'; \
      printf 'jsonlite_version\t%s\n' '2.0.0'; \
      printf 'curl_debian_version\t%s\n' "${CURL_DEB_VERSION}"; \
      printf 'coloc_source_commit\t%s\n' "${R0_COLOC_SOURCE_COMMIT}"; \
      printf 'coloc_susie_R_sha256\t%s\n' '2fe466c74bdb3bedf91c5cd088ca5c3aa79e3f0733ef090839a4fefd078a93a9'; \
    } > /opt/build-manifest.tsv \
 && chmod 0444 /opt/install-Rpkgs.R /opt/Renv-manifest.tsv \
      /opt/system-manifest.tsv /opt/build-manifest.tsv \
 && groupadd --gid "${APP_GID}" analyst \
 && useradd --uid "${APP_UID}" --gid "${APP_GID}" --create-home --shell /bin/bash analyst

USER analyst
WORKDIR /workspace
CMD ["R", "--vanilla"]
