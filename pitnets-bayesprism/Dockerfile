# Bayesian deconvolution environment for the PitNET atlas.
#
# Built FROM the validated analysis image by digest. The base image is not
# modified, so every completed analysis remains reproducible with the original
# SIF.
#
# BayesPrism is the primary bulk deconvolution method per the frozen spec
# (bulk_deconvolution_reference_spec_20260824.md): it takes the full
# cells-by-genes raw count reference plus cell-type and cell-state labels. Donor
# states represent malignant heterogeneity in the initial Gibbs pass; version
# 2.2.3 exposes final updated fractions only at cell-type level, so lineage is
# estimated separately from recovered malignant expression. The two collapsed
# signature matrices from the same spec serve as linear cross-checks and need
# no special environment.
#
# BayesPrism is installed from a GitHub archive fetched by commit SHA, never via
# remotes::install_github, which would honour Remotes fields and fetch further
# unpinned packages. The DESCRIPTION version is asserted before installation;
# a mismatch fails the build rather than silently moving on.

FROM ghcr.io/cyl-logan-lab/pitnets-grf@sha256:9d11f285d9a98e753f362d784d0bc7ec0097cc338f7b77b3d2f83b636bdc9aff

LABEL org.opencontainers.image.source="https://github.com/CYL-Logan-Lab/docker-images"
LABEL org.opencontainers.image.description="PitNET bulk deconvolution: BayesPrism on top of the validated PitNET analysis image"
LABEL org.opencontainers.image.base.name="ghcr.io/cyl-logan-lab/pitnets-grf@sha256:9d11f285d9a98e753f362d784d0bc7ec0097cc338f7b77b3d2f83b636bdc9aff"

ENV BAYESPRISM_COMMIT=19052052a6f30833b27e2148294459b0ba2f923e \
    BAYESPRISM_VERSION=2.2.3 \
    SNOWFALL_VERSION=1.84.6.3 \
    GPLOTS_VERSION=3.3.0 \
    SCRAN_VERSION=1.38.1 \
    BIOCPARALLEL_VERSION=1.44.0 \
    DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# snowfall and gplots are installed from the same date-frozen Posit snapshot
# the base image used, asserted below rather than inherited implicitly.
# scran and BiocParallel come from the pinned Bioconductor release already
# asserted in the base. Runtime analysis never installs packages; the snapshot
# remains in the image environment as provenance and is asserted by smoke.R.
ENV CRAN_SNAPSHOT=https://packagemanager.posit.co/cran/__linux__/noble/2026-08-06
RUN Rscript --vanilla -e 'options(repos = c(CRAN = Sys.getenv("CRAN_SNAPSHOT"))); \
    if (!grepl("packagemanager.posit.co/cran/.*/[0-9]{4}-[0-9]{2}-[0-9]{2}", Sys.getenv("CRAN_SNAPSHOT"))) stop("CRAN_SNAPSHOT is not a dated snapshot"); \
    install.packages(c("snowfall", "gplots"), quiet = TRUE); \
    if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager", quiet = TRUE); \
    BiocManager::install(c("scran", "BiocParallel"), ask = FALSE, update = FALSE); \
    expected <- c(snowfall = Sys.getenv("SNOWFALL_VERSION"), \
                  gplots = Sys.getenv("GPLOTS_VERSION"), \
                  scran = Sys.getenv("SCRAN_VERSION"), \
                  BiocParallel = Sys.getenv("BIOCPARALLEL_VERSION")); \
    for (p in names(expected)) { \
      if (!requireNamespace(p, quietly = TRUE)) stop("failed to install ", p); \
      found <- as.character(packageVersion(p)); \
      if (found != expected[[p]]) stop(p, " version drift: found ", found, \
                                       " expected ", expected[[p]]); \
      cat(p, found, "\n") \
    }'

RUN curl -fsSL -o /tmp/bayesprism.tar.gz \
      "https://github.com/Danko-Lab/BayesPrism/archive/${BAYESPRISM_COMMIT}.tar.gz" \
    && rm -rf /tmp/BayesPrism-src \
    && mkdir -p /tmp/BayesPrism-src \
    && tar -xzf /tmp/bayesprism.tar.gz -C /tmp/BayesPrism-src --strip-components=1 \
    && Rscript --vanilla -e ' \
      desc <- read.dcf("/tmp/BayesPrism-src/BayesPrism/DESCRIPTION"); \
      if (desc[1, "Version"] != Sys.getenv("BAYESPRISM_VERSION")) \
        stop("BayesPrism version drift: found ", desc[1, "Version"], \
             " expected ", Sys.getenv("BAYESPRISM_VERSION")); \
      install.packages("/tmp/BayesPrism-src/BayesPrism", repos = NULL, type = "source")' \
    && rm -rf /tmp/bayesprism.tar.gz /tmp/BayesPrism-src
