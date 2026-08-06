# ============================================================================
# R environment for t2d-sc-lipid (snRNA-seq annotation pipeline, Seurat v5).
# Downstream project: https://github.com/CYL-Logan-Lab/t2d-sc-lipid
#
# ── The unit of reproducibility is the image, not "rebuild and get the same" ─
# Downstream pins the image by digest, and a digest is content-addressed, so
# "which environment produced this analysis" always has an exact answer. This
# recipe's job is to make the image buildable and to make the built image match
# its own claims (version mismatch fails the build). It does NOT promise that
# rebuilding six months from now yields a byte-identical image -- see pin 3.
#
# ── Three pinning layers ────────────────────────────────────────────────────
#   1. Base image taken by **OCI manifest digest**, not by the :5.5.1 tag. A tag
#      is a mutable reference: the maintainer re-pushes it and you silently get
#      a different image. A digest cannot change. R 4.5.2 / Seurat 5.5.1 come
#      from this layer, and the install script **asserts** both versions up
#      front, so swapping the base image fails the build instead of quietly
#      producing a different environment.
#   2. CRAN goes through Posit's **date-frozen** snapshot (Ubuntu noble
#      binaries). With a rolling mirror such as cloud.r-project.org, the same
#      Dockerfile would install different code today and six months from now.
#   3. Bioconductor has no dated snapshot service, only per-release-branch
#      repositories -- the Bioc version is nailed down by the URL below, but the
#      release branch itself keeps rolling out patch versions. So every direct
#      dependency gets an **explicit version assertion**; a mismatch fails the
#      build. Be clear about the limit of this layer: the assertions cover only
#      the packages named here. Transitive dependencies pulled in by Bioc are
#      NOT pinned; their patch versions can drift without failing the build, and
#      the drift shows up only in /opt/Renv-manifest.tsv inside the image. So
#      "the same recipe rebuilds to the same environment" is false for this
#      file; what is true is "downstream, pinned by digest, always gets the same
#      environment".
#      A failed assertion means upstream moved: write the new version into
#      PKG_PINNED and rebuild -- do **not** delete the assertion.
#
# ── Why add anything on top of satijalab/seurat ─────────────────────────────
# The project does nucleus-level doublet scoring with scDblFinder. The base
# image ships neither scDblFinder nor its dependencies (scran, scuttle, scater,
# bluster, edgeR, BiocNeighbors, BiocSingular, metapod, ScaledMatrix) nor
# xgboost from CRAN.
#
# ── The smoke test lives outside this file ──────────────────────────────────
# The install layer below does run library() once, but only when that layer is
# actually built: a cache hit skips the whole layer, and putting the test in its
# own RUN does not change that (cache matching walks parent layers in order).
# For "every CI run really verifies it", the test has to run outside the
# Dockerfile -- see the smoke-test step in .github/workflows/build.yml, which
# docker-runs the image this build actually produced.
# ============================================================================
FROM satijalab/seurat@sha256:048d965487afc2961c450879692281a73e24f6de47360ed2f11b31112ebd844e

LABEL org.opencontainers.image.source="https://github.com/CYL-Logan-Lab/docker-images"
LABEL org.opencontainers.image.description="R env for CYL-Logan-Lab/t2d-sc-lipid: Seurat 5.5.1 + scDblFinder"
LABEL org.opencontainers.image.base.name="satijalab/seurat@sha256:048d965487afc2961c450879692281a73e24f6de47360ed2f11b31112ebd844e"

ENV LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# The installer is its own file rather than a heredoc: as plain install-Rpkgs.R
# it gets R syntax highlighting, linting and `Rscript -e 'parse(...)'` for free,
# none of which work on text embedded in a Dockerfile. Build-cache behaviour is
# the same either way -- the layer key is the file's content, so editing the
# script invalidates the install layer and nothing else does.
COPY install-Rpkgs.R /opt/install-Rpkgs.R

RUN Rscript --vanilla /opt/install-Rpkgs.R \
 && chmod 0444 /opt/Renv-manifest.tsv /opt/install-Rpkgs.R
