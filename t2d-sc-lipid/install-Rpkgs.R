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

# install.packages rather than BiocManager::install: all three repositories are
# attached to `repos`, so the CRAN dependencies of Bioc packages also land in
# the frozen snapshot, and provenance is stated in one place.
# (BiocManager::install(ask = FALSE, update = FALSE) would also be
# non-interactive and non-upgrading; this just avoids a second resolver.)
# The Bioc version is nailed down by this URL, not by BiocManager's default.
#
# BIOCANN is a **separate** Bioconductor repository from BIOC. Annotation
# packages (org.*.eg.db, GO.db, reactome.db) do not live in the software
# repository, so without this line install.packages() reports them as
# unavailable and the assertion block below is what turns that into a build
# failure. It is pinned to the same 3.22 release as BIOC.
options(repos = c(BIOC = "https://bioconductor.org/packages/3.22/bioc",
                  BIOCANN = "https://bioconductor.org/packages/3.22/data/annotation",
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
  scDblFinder   = "1.24.10",

  # ── Pathway enrichment (added for the ASPC state characterisation step) ────
  # The gene sets ship *inside* org.Hs.eg.db / GO.db / reactome.db, which is the
  # whole point of choosing them: an enrichment run needs no network at analysis
  # time, and the gene-set version is fixed by the image digest like everything
  # else. msigdbr was considered and rejected -- since 26.x it fetches gene sets
  # over the network at call time, which would make the result depend on the day
  # the analysis ran rather than on the image.
  #
  # DOSE / GOSemSim / AnnotationDbi / graphite are pinned even though nothing
  # here calls them by name: clusterProfiler, enrichplot and ReactomePA are thin
  # over them (the enrichment result class itself is DOSE's, the term-similarity
  # step used when collapsing redundant GO terms is GOSemSim's, every annotation
  # query goes through AnnotationDbi, and ReactomePA's pathway topology comes
  # from graphite). An unpinned one of these drifting is exactly the kind of
  # silent change that alters enrichment output, so they get the same treatment
  # as everything else. The base image also predates them, so leaving them
  # unnamed risks keeping whatever version happened to come along for the ride.
  AnnotationDbi   = "1.72.0",
  GO.db           = "3.22.0",
  org.Hs.eg.db    = "3.22.0",
  reactome.db     = "1.95.0",
  GOSemSim        = "2.36.0",
  DOSE            = "4.4.0",
  graphite        = "1.56.0",
  clusterProfiler = "4.18.4",
  ReactomePA      = "1.54.0",
  enrichplot      = "1.30.5",
  fgsea           = "1.36.2"
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

# Loadable does not mean usable either -- the annotation packages are SQLite
# databases behind an R facade, and a truncated download gives you a package
# that attaches cleanly and then fails on the first query. So query them once,
# here, with a gene that is not going anywhere. GAPDH is entrez 2597; asking for
# its GO terms exercises org.Hs.eg.db, GO.db and AnnotationDbi's select() path
# in one call.
gapdh <- AnnotationDbi::select(org.Hs.eg.db::org.Hs.eg.db, keys = "GAPDH",
                               keytype = "SYMBOL", columns = c("ENTREZID", "GO"))
stopifnot(nrow(gapdh) > 0, unique(gapdh$ENTREZID) == "2597")
stopifnot(length(AnnotationDbi::keys(GO.db::GO.db)) > 40000,
          length(AnnotationDbi::keys(reactome.db::reactome.db, "PATHID")) > 20000)
cat("annotation databases queryable:", nrow(gapdh), "GO rows for GAPDH\n")

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
             paste0("# Bioc annotation repo: ", getOption("repos")[["BIOCANN"]]),
             "package\tversion\tlibpath",
             apply(ip, 1, paste, collapse = "\t")),
           "/opt/Renv-manifest.tsv")
cat("manifest written to /opt/Renv-manifest.tsv,", nrow(ip), "packages\n")
