# Copy-number inference environment for the PitNET atlas.
#
# This image is a strict superset of the validated analysis image and is built
# FROM that image by digest. The base image is not modified and not repointed,
# so every completed analysis (Slurm jobs 52272-52342) remains reproducible with
# the original SIF.
#
# Adds: JAGS and rjags, inferCNV, CaSpER pinned to a specific commit, and the
# BAFExtract allele-frequency tool built from a pinned commit.

FROM ghcr.io/cyl-logan-lab/pitnets-grf@sha256:9d11f285d9a98e753f362d784d0bc7ec0097cc338f7b77b3d2f83b636bdc9aff

LABEL org.opencontainers.image.source="https://github.com/CYL-Logan-Lab/docker-images"
LABEL org.opencontainers.image.description="PitNET copy-number inference: inferCNV, CaSpER and BAFExtract on top of the validated PitNET analysis image"
LABEL org.opencontainers.image.base.name="ghcr.io/cyl-logan-lab/pitnets-grf@sha256:9d11f285d9a98e753f362d784d0bc7ec0097cc338f7b77b3d2f83b636bdc9aff"

ENV CASPER_COMMIT=8aae116f2fa5cb55ac62259633b246b9d7b021b4 \
    BAFEXTRACT_COMMIT=4736003783095a82732f427e97c741053df084af \
    CASPER_REPO=https://github.com/akdess/CaSpER \
    BAFEXTRACT_REPO=https://github.com/akdess/BAFExtract \
    DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# JAGS is a system dependency of rjags, which inferCNV needs for its HMM.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        jags \
        libjags-dev \
        build-essential \
        git \
        zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

COPY install-cnv-Rpkgs.R /opt/pitnets-cnv/install-cnv-Rpkgs.R
RUN Rscript --vanilla /opt/pitnets-cnv/install-cnv-Rpkgs.R

COPY build-baf-tools.sh /opt/pitnets-cnv/build-baf-tools.sh
RUN chmod +x /opt/pitnets-cnv/build-baf-tools.sh && /opt/pitnets-cnv/build-baf-tools.sh

# smoke.R is deliberately not copied in. CI mounts it and runs it against the
# image this build produced, so a cache hit cannot skip verification.

CMD ["R"]
