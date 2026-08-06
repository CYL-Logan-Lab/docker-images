# syntax=docker/dockerfile:1.7
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

# The installer lands in the image as a file rather than as a RUN heredoc:
# Rscript does not read a script from stdin, it needs a path. Side benefit --
# the recipe ships with the image, so "how was this environment built" can be
# answered from inside the container.
COPY <<'EOF' /opt/install-Rpkgs.R
# ── Assertion for pin 1: the base image must still be that base image ────────
# FROM names a digest, so normally nothing moves. But the header of this file
# *states in prose* R 4.5.2 / Seurat 5.5.1, and a stated claim should be
# executable. If someone bumps the digest and forgets the prose, this fails
# immediately.
stopifnot(
  getRversion() == "4.5.2",
  utils::packageVersion("Seurat") == "5.5.1"
)

# install.packages rather than BiocManager::install: both repositories are
# attached to `repos`, so the CRAN dependencies of Bioc packages also land in
# the frozen snapshot, and provenance is stated in one place.
# (BiocManager::install(ask = FALSE, update = FALSE) would also be
# non-interactive and non-upgrading; this just avoids a second resolver.)
# The Bioc version is nailed down by this URL, not by BiocManager's default.
options(repos = c(BIOC = "https://bioconductor.org/packages/3.22/bioc",
                  CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/2026-08-06"),
        Ncpus = 4)

# Listing them in dependency order is for humans; the real order comes from
# install.packages resolving dependencies itself.
PKG_PINNED <- c(
  xgboost       = "3.2.1.1",   # CRAN snapshot
  BiocNeighbors = "2.4.0",
  BiocSingular  = "1.26.1",
  ScaledMatrix  = "1.18.0",
  metapod       = "1.18.0",
  edgeR         = "4.8.2",
  scuttle       = "1.20.0",
  bluster       = "1.20.0",
  scran         = "1.38.1",
  scater        = "1.38.1",
  scDblFinder   = "1.24.10"
)

install.packages(names(PKG_PINNED))

# ── Assertion: what got installed must be what this file says ────────────────
# This block is not optional. install.packages() only *warns* when a package
# fails to install and still exits 0, so without an assertion the build would
# succeed, the image would ship, and the missing package would surface months
# later in the middle of an analysis. The check covers both "did it install"
# and "is it the stated version".
got <- vapply(names(PKG_PINNED), function(p)
  tryCatch(as.character(utils::packageVersion(p)),
           error = function(e) NA_character_), character(1))
bad <- is.na(got) | got != PKG_PINNED
if (any(bad)) {
  stop("package versions disagree with the Dockerfile:\n",
       paste(sprintf("  %-14s expected %-10s got %s",
                     names(PKG_PINNED)[bad], PKG_PINNED[bad],
                     ifelse(is.na(got[bad]), "<not installed>", got[bad])),
             collapse = "\n"),
       "\nUpstream moved. Write the new versions into PKG_PINNED and rebuild;",
       "\ndo not delete this assertion.")
}

# Installable does not mean loadable: with a missing C-level dependency the
# package installs fine and library() is what blows up.
# Note this only runs when this layer is actually built; a cache hit skips it.
# The per-CI-run verification lives in the workflow -- see the header.
invisible(lapply(names(PKG_PINNED), function(p)
  library(p, character.only = TRUE, quietly = TRUE)))

# ── Bake the manifest into the image ─────────────────────────────────────────
# It records the **whole library**, not just the packages named above: Bioc
# drags in a chain of transitive dependencies, and those are exactly what the
# assertions do not cover. The manifest cannot hold them still, but it can at
# least answer afterwards "which version was in there". When something breaks,
# the culprit is usually one of the packages nobody named.
bioc <- tryCatch(as.character(BiocManager::version()),
                 error = function(e) "(BiocManager not in the image)")
ip <- utils::installed.packages()[, c("Package", "Version", "LibPath"), drop = FALSE]
ip <- ip[order(ip[, "Package"]), , drop = FALSE]
dir.create("/opt", showWarnings = FALSE)
writeLines(c("# R package manifest for this image, generated at build time by /opt/install-Rpkgs.R",
             paste0("# R: ", R.version.string),
             paste0("# BiocManager: ", bioc),
             paste0("# CRAN: ", getOption("repos")[["CRAN"]]),
             paste0("# Bioc repo: ", getOption("repos")[["BIOC"]]),
             "package\tversion\tlibpath",
             apply(ip, 1, paste, collapse = "\t")),
           "/opt/Renv-manifest.tsv")
cat("manifest written to /opt/Renv-manifest.tsv,", nrow(ip), "packages\n")
EOF

RUN Rscript --vanilla /opt/install-Rpkgs.R \
 && chmod 0444 /opt/Renv-manifest.tsv /opt/install-Rpkgs.R
