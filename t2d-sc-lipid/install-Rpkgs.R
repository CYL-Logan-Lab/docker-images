# Package installation for the image built by the Dockerfile next to this file.
# It ships inside the image at /opt/install-Rpkgs.R, so "how was this
# environment built" can be answered from inside the container. Read the
# Dockerfile header first: it explains the three pinning layers this script
# implements.

# ── Assertion for pin 1: the base image must still be that base image ────────
# FROM names a digest, so normally nothing moves. But the Dockerfile header
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
