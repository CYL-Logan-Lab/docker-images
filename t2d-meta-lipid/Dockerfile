# Minimal R0 environment for CYL-Logan-Lab/Logan-T2D-Genomic.
# The downstream Docker Compose project name is t2d-meta-lipid.
#
# Reproducibility layers:
#   1. R 4.5.2 base image is pinned by OCI digest.
#   2. CRAN packages come from the 2026-08-06 Posit snapshot.
#   3. Every package used directly by R0 has an exact version assertion.
# The full resolved R and Debian package inventories are baked into /opt.
FROM rocker/r-ver@sha256:fd4ccdd3a4a6f7ef805e2daeee2a0fe3bf126bc231f36351223baecf5a595a4c

LABEL org.opencontainers.image.source="https://github.com/CYL-Logan-Lab/docker-images"
LABEL org.opencontainers.image.description="Minimal Docker-only R0 feasibility environment for Logan-T2D-Genomic"
LABEL org.opencontainers.image.base.name="rocker/r-ver@sha256:fd4ccdd3a4a6f7ef805e2daeee2a0fe3bf126bc231f36351223baecf5a595a4c"

ARG APP_UID=1000
ARG APP_GID=1000
ARG COLOC_SOURCE_COMMIT=50fe5291fea7f8ab49823bd86747385d6e56870f

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

COPY install-Rpkgs.R /opt/install-Rpkgs.R

# GRCh37 -> GRCh38 point conversion is required by the R0 pilot. The versioned
# UCSC binary is checksum-gated before it can enter a successful image.
ADD --chmod=0755 https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64.v482/liftOver /usr/local/bin/liftOver

RUN sha256sum /usr/local/bin/liftOver \
 && echo '6a8deb81d26de3b5f25da69a1a5fa4754432817b768ca3430254109d2379efe0  /usr/local/bin/liftOver' | sha256sum -c - \
 && liftOver 2>&1 | head -n 1 \
 && Rscript --vanilla /opt/install-Rpkgs.R \
 && dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort > /opt/system-manifest.tsv \
 && { \
      printf 'base_image\t%s\n' 'rocker/r-ver@sha256:fd4ccdd3a4a6f7ef805e2daeee2a0fe3bf126bc231f36351223baecf5a595a4c'; \
      printf 'r_version\t%s\n' '4.5.2'; \
      printf 'python\t%s\n' 'PYTHON_NOT_INSTALLED'; \
      printf 'cran_snapshot\t%s\n' "${R0_CRAN_REPO}"; \
      printf 'coloc_version\t%s\n' '6.0.1'; \
      printf 'coloc_source_commit\t%s\n' "${R0_COLOC_SOURCE_COMMIT}"; \
      printf 'coloc_susie_R_sha256\t%s\n' '2fe466c74bdb3bedf91c5cd088ca5c3aa79e3f0733ef090839a4fefd078a93a9'; \
      printf 'liftover_version\t%s\n' '482'; \
      printf 'liftover_sha256\t%s\n' '6a8deb81d26de3b5f25da69a1a5fa4754432817b768ca3430254109d2379efe0'; \
    } > /opt/build-manifest.tsv \
 && chmod 0555 /usr/local/bin/liftOver \
 && chmod 0444 /opt/install-Rpkgs.R /opt/Renv-manifest.tsv \
      /opt/system-manifest.tsv /opt/build-manifest.tsv \
 && groupadd --gid "${APP_GID}" analyst \
 && useradd --uid "${APP_UID}" --gid "${APP_GID}" --create-home --shell /bin/bash analyst

USER analyst
WORKDIR /workspace
CMD ["R", "--vanilla"]
