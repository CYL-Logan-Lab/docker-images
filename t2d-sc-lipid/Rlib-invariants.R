# Packages whose versions must NOT move while other packages are installed on
# top. Most came from the base image; scDblFinder is installed by
# install-Rpkgs.R and then held still like the rest. Sourced by both installers
# (see the Dockerfile header); it ships inside the image at
# /opt/Rlib-invariants.R.
#
# ── Why this exists ──────────────────────────────────────────────────────────
# install.packages() upgrades an already-installed package without being asked
# whenever some new dependency declares a higher minimum. That is not
# hypothetical here: the frozen CRAN snapshot carries Matrix 1.7-6 while the base
# image ships 1.7-5, so any newly added package declaring `Matrix (>= 1.7-6)`
# silently replaces it. Matrix is the sparse linear algebra under IRLBA, i.e.
# under every PCA / neighbour graph / UMAP the downstream project has already
# run, so an unnoticed bump would move numerical results in steps that were
# never re-run and never re-inspected.
#
# The downstream project asserts six of these at container-pull time
# (code/00_setup/05_setup_seurat_env.sh pins Seurat, SeuratObject, harmony,
# Matrix, presto, scDblFinder). This file asserts those six plus the six
# numerical libraries below -- a superset, not the same list, and deliberately
# so: downstream checks what its own scripts call by name, while a build has to
# catch things nothing calls by name. Asserting here is what makes the
# downstream check cheap: a violation fails at build time, where it is one line
# in a CI log, instead of after publishing, where it is a retracted digest.
#
# The claim being defended is narrow and worth stating exactly: adding the
# cell-cell communication stack did not disturb the numerical chain that steps
# 1-33 ran on. It says nothing about the transitive dependencies nobody named --
# those are recorded in /opt/Renv-manifest.tsv and are not held still.

R_INVARIANT <- "4.5.2"

PKG_INVARIANT <- c(
  Seurat       = "5.5.1",
  SeuratObject = "5.4.0",
  Matrix       = "1.7-5",   # the one that is actually at risk; see above
  harmony      = "2.0.5",
  presto       = "1.0.0",
  scDblFinder  = "1.24.10", # installed by install-Rpkgs.R, not from the base image

  # The numerical libraries the results actually rest on: irlba computes the
  # truncated SVD behind RunPCA, uwot the UMAP embedding, igraph the Louvain
  # partition, and Rcpp/RcppEigen/RcppArmadillo are the compiled backends that
  # Seurat, harmony and presto link against. Listing them is not decoration --
  # without them this function would pass while an unnamed transitive dependency
  # had quietly upgraded the thing under every PCA in the project, and the build
  # would print "numerical chain intact" on its way to publishing.
  #
  # None of these can fail spuriously, and that was checked rather than assumed.
  # The check is: across every pinned repository, what is the highest minimum
  # any package declares for each name below? Re-run it before adding a package
  # here -- an assertion that fires when nothing is wrong gets deleted, which is
  # worse than not having written it.
  #
  # Re-run for v5 on 2026-08-11, now over **four** repositories (Bioc 3.22
  # software + annotation + experiment, and the frozen CRAN snapshot; 28251
  # index entries). Highest minimum declared anywhere, against what is
  # installed:
  #
  #   Seurat        5.4.0     < 5.5.1        SeuratObject  5.3.0    < 5.4.0
  #   Matrix        1.7-4     < 1.7-5        harmony       1.2.0    < 2.0.5
  #   scDblFinder   1.20.0    < 1.24.10      irlba         2.3.5    < 2.3.7
  #   igraph        2.2.2     < 2.3.2        Rcpp          1.1.1-1.1 = 1.1.1.1.1
  #   RcppEigen     0.3.4.0.0 < 0.3.4.0.2    RcppArmadillo 15.2.6-1 < 15.4.0.1
  #   uwot          0.2.4     = 0.2.4        presto        (nothing declares it)
  #
  # Every one is at or below what is installed, so nothing in reach can force an
  # upgrade. Two sit exactly *at* the installed version rather than below it
  # (uwot, Rcpp) -- still safe, because install.packages() upgrades only to
  # satisfy an unmet minimum and these are met, but they are the two with no
  # headroom, so they are the two to re-check first next time.
  #
  # What v5 added to the reachable set: the co-expression / TF / trajectory /
  # bulk stack (WGCNA, hdWGCNA and its closure, decoupleR, dorothea, slingshot,
  # UCell, GSVA, sva, glmnet, hgu219.db). Restricted to just that closure --
  # 65 packages -- the highest minimums are lower still: Matrix 1.5-0 (GSVA),
  # igraph 2.0.0 (graphlayouts), Rcpp 0.11.0 (WGCNA), and nothing at all for the
  # other nine.
  #
  # What v6 adds is two packages and it does not move this list. limma declares
  # only `statmod`, metafor declares `Matrix` with **no version at all**, and of
  # metafor's closure only metadat is not already installed (it Imports utils,
  # tools and mathjaxr). So nothing newly reachable declares a minimum on any
  # name below, and the six-package re-check above stands unchanged. v6 also
  # adds a Python venv, which cannot interact with this at all: it is a separate
  # interpreter with its own hash-locked closure and no R package sees it.
  irlba         = "2.3.7",
  uwot          = "0.2.4",
  igraph        = "2.3.2",
  Rcpp          = "1.1.1.1.1",
  RcppEigen     = "0.3.4.0.2",
  RcppArmadillo = "15.4.0.1"
)

# `stage` names the point in the build this ran at, so a failure says which layer
# moved things rather than only that something did.
#
# Comparison goes through numeric_version rather than string equality on
# purpose: R normalises the separator when printing, so Matrix 1.7-5 renders as
# "1.7.5" and a string compare against the DESCRIPTION spelling "1.7-5" would
# report a mismatch that does not exist. numeric_version treats "-" and "." as
# the same separator and compares the components.
assert_invariants <- function(stage) {
  if (getRversion() != R_INVARIANT)
    stop("R itself moved (", stage, "): expected ", R_INVARIANT,
         ", got ", as.character(getRversion()), call. = FALSE)

  got <- vapply(names(PKG_INVARIANT), function(p)
    tryCatch(as.character(utils::packageVersion(p)),
             error = function(e) NA_character_), character(1))

  # Two steps rather than one `is.na(got) | ...`: numeric_version() errors on NA
  # instead of propagating it, so a package that is missing entirely would abort
  # here with "invalid version specification" instead of reaching the message
  # below that says which package is missing.
  present <- !is.na(got)
  bad <- !present
  bad[present] <- numeric_version(got[present]) !=
                  numeric_version(PKG_INVARIANT[present])

  if (any(bad))
    stop("the numerical chain moved (", stage, "):\n",
         paste(sprintf("  %-13s expected %-9s got %s",
                       names(PKG_INVARIANT)[bad], PKG_INVARIANT[bad],
                       ifelse(is.na(got[bad]), "<not installed>", got[bad])),
               collapse = "\n"),
         "\nSomething installed here declared a higher minimum and upgraded it.",
         "\nSteps 1-33 downstream ran on the versions above, so do NOT relax this",
         "\nassertion to make the build pass: pin the offending package lower, or",
         "\naccept the bump deliberately and record it in the decision log.",
         call. = FALSE)

  cat("numerical chain intact (", stage, "): ",
      paste(names(PKG_INVARIANT), got, collapse = ", "), "\n", sep = "")
}
