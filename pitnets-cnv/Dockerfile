# Copy-number inference environment for the PitNET atlas.
#
# This image is a strict superset of the validated analysis image and is built
# FROM that image by digest. The base image is not modified and not repointed,
# so every completed analysis (Slurm jobs 52272-52342) remains reproducible with
# the original SIF.
#
# Two independent methods are provided so that copy-number calls can be
# cross-checked rather than trusted from a single algorithm:
#   inferCNV  expression HMM against a normal reference (needs JAGS)
#   copyKAT   Bayesian segmentation with mixture modelling, pure R
#
# CaSpER was evaluated and dropped. Its allele-frequency tool BAFExtract reads a
# SAM stream as a single sample and has no cell-barcode awareness, so on 10x data
# it cannot deliver the allele-aware validation that would have justified the
# extra dependency surface.
#
# Ubuntu noble ships JAGS as a single `jags` package that already contains the
# headers, the shared library and a pkg-config file; there is no libjags-dev.

FROM ghcr.io/cyl-logan-lab/pitnets-grf@sha256:9d11f285d9a98e753f362d784d0bc7ec0097cc338f7b77b3d2f83b636bdc9aff

LABEL org.opencontainers.image.source="https://github.com/CYL-Logan-Lab/docker-images"
LABEL org.opencontainers.image.description="PitNET copy-number inference: inferCNV and copyKAT on top of the validated PitNET analysis image"
LABEL org.opencontainers.image.base.name="ghcr.io/cyl-logan-lab/pitnets-grf@sha256:9d11f285d9a98e753f362d784d0bc7ec0097cc338f7b77b3d2f83b636bdc9aff"

ENV COPYKAT_COMMIT=01924c0999bb660064da8d3e1561615ac6efb76f \
    DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends jags \
 && rm -rf /var/lib/apt/lists/* \
 && pkg-config --exists jags

COPY install-cnv-Rpkgs.R /opt/pitnets-cnv/install-cnv-Rpkgs.R
RUN Rscript --vanilla /opt/pitnets-cnv/install-cnv-Rpkgs.R

# smoke.R is deliberately not copied in. CI mounts it and runs it against the
# image this build produced, so a cache hit cannot skip verification.

CMD ["R"]
