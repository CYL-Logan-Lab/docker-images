# Downstream multi-omics analysis environment for PitNETs_GRF.
#
# Scope: processed scRNA-seq, spatial transcriptomics, bulk RNA-seq and
# Nanopore direct-RNA-sequencing results. Raw-data tools such as Cell Ranger,
# basecallers and aligners are intentionally excluded.
#
# The base is the laboratory's published single-cell image pinned by digest.
# It contributes R 4.5.2, Seurat 5.5.1, Bioconductor 3.22, enrichment,
# cell-cell communication, trajectory and gene-program analysis. This image
# adds spatial containers/statistics, bulk/isoform analysis, genomic ranges and
# a separate hash-locked Python environment for Scanpy/SpatialData/DRS tables.
FROM ghcr.io/cyl-logan-lab/t2d-sc-lipid@sha256:4778424e1250760bfe1f8557e4e60b055dddff7cca6ad761cc5b3073a29e7667

LABEL org.opencontainers.image.source="https://github.com/CYL-Logan-Lab/docker-images"
LABEL org.opencontainers.image.description="Downstream PitNET multi-omics analysis: scRNA-seq, spatial transcriptomics, bulk RNA-seq, Nanopore DRS results and publication graphics"
LABEL org.opencontainers.image.base.name="ghcr.io/cyl-logan-lab/t2d-sc-lipid@sha256:4778424e1250760bfe1f8557e4e60b055dddff7cca6ad761cc5b3073a29e7667"

ENV PITNETS_PYENV_DIR=/opt/pitnets-pyenv \
    MPLBACKEND=Agg \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

COPY install-Rpkgs.R /opt/pitnets-grf-install-Rpkgs.R
RUN Rscript --vanilla /opt/pitnets-grf-install-Rpkgs.R

COPY requirements-py.in requirements-py.txt pyenv-verify.py install-pypkgs.sh /opt/pitnets-grf/
RUN /opt/pitnets-grf/install-pypkgs.sh

CMD ["R"]
