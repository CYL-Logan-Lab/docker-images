#!/usr/bin/env Rscript

# R packages for copy-number inference.
#
# Installs only what the base image is missing, so the layer stays small and the
# already-validated package set is not disturbed. Every install is verified by
# loading the package; a failure aborts the build rather than producing an image
# that silently lacks a tool.

options(
  warn = 2,
  repos = c(CRAN = "https://cloud.r-project.org"),
  Ncpus = max(1L, parallel::detectCores())
)

message("R: ", R.version.string)
message("Bioconductor: ", as.character(BiocManager::version()))

install_if_missing <- function(packages, installer) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (!length(missing)) {
    message("Already present: ", paste(packages, collapse = ", "))
    return(invisible(NULL))
  }
  message("Installing: ", paste(missing, collapse = ", "))
  installer(missing)
  invisible(NULL)
}

cran_packages <- c(
  "rjags", "signal", "reshape", "mclust", "ggpubr", "intergraph",
  "ggnetwork", "ape", "pheatmap", "RColorBrewer", "scales", "gridExtra",
  "igraph", "Rcpp", "futile.logger", "coda", "argparse", "fitdistrplus"
)
install_if_missing(cran_packages, function(pkgs) {
  install.packages(pkgs, dependencies = TRUE)
})

bioc_packages <- c(
  "infercnv", "GenomicRanges", "IRanges", "limma", "biomaRt",
  "GO.db", "org.Hs.eg.db", "GOstats", "SingleCellExperiment"
)
install_if_missing(bioc_packages, function(pkgs) {
  BiocManager::install(pkgs, ask = FALSE, update = FALSE)
})

# CaSpER is not on CRAN or Bioconductor and is pinned to an explicit commit.
casper_commit <- Sys.getenv("CASPER_COMMIT")
if (!nzchar(casper_commit)) stop("CASPER_COMMIT is not set")
if (!requireNamespace("CaSpER", quietly = TRUE)) {
  message("Installing CaSpER at commit ", casper_commit)
  remotes::install_github(paste0("akdess/CaSpER@", casper_commit),
                          upgrade = "never", dependencies = TRUE)
}

# rjags must find the JAGS shared library installed in the previous layer.
required <- c("rjags", "infercnv", "CaSpER", "GenomicRanges", "limma", "mclust", "signal")
message("Verifying package loading")
for (package in required) {
  suppressPackageStartupMessages(library(package, character.only = TRUE))
  message("  ", package, " ", as.character(utils::packageVersion(package)))
}

versions <- data.frame(
  package = required,
  version = vapply(required, function(p) as.character(utils::packageVersion(p)), character(1)),
  stringsAsFactors = FALSE
)
versions <- rbind(
  versions,
  data.frame(package = "R", version = paste(R.version$major, R.version$minor, sep = "."),
             stringsAsFactors = FALSE),
  data.frame(package = "Bioconductor", version = as.character(BiocManager::version()),
             stringsAsFactors = FALSE),
  data.frame(package = "CaSpER_commit", version = casper_commit, stringsAsFactors = FALSE)
)
dir.create("/opt/pitnets-cnv", recursive = TRUE, showWarnings = FALSE)
write.table(versions, "/opt/pitnets-cnv/r-package-versions.tsv",
            sep = "\t", quote = FALSE, row.names = FALSE)
message("All copy-number R packages installed and loadable")
