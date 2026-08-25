#!/usr/bin/env Rscript

# R packages for copy-number inference.
#
# Only what the base image lacks is installed, so the validated package set is
# left alone. Every install is verified by loading the package: a failure aborts
# the build rather than producing an image that silently lacks a tool.

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

# rjags is compiled against the JAGS headers installed in the previous layer.
# copyKAT's declared imports follow; none of them needs a system library.
cran_packages <- c(
  "rjags", "coda",
  "parallelDist", "dlm", "gplots", "mixtools", "cluster", "MCMCpack", "transport",
  "RColorBrewer", "futile.logger", "argparse", "fitdistrplus", "ape", "phyclust"
)
install_if_missing(cran_packages, function(pkgs) install.packages(pkgs, dependencies = TRUE))

bioc_packages <- c("infercnv", "GenomicRanges", "IRanges", "SingleCellExperiment", "edgeR")
install_if_missing(bioc_packages, function(pkgs) {
  BiocManager::install(pkgs, ask = FALSE, update = FALSE)
})

# copyKAT is not on CRAN or Bioconductor and is pinned to an explicit commit.
copykat_commit <- Sys.getenv("COPYKAT_COMMIT")
if (!nzchar(copykat_commit)) stop("COPYKAT_COMMIT is not set")
if (!requireNamespace("copykat", quietly = TRUE)) {
  message("Installing copykat at commit ", copykat_commit)
  remotes::install_github(paste0("navinlabcode/copykat@", copykat_commit),
                          upgrade = "never", dependencies = TRUE)
}

required <- c("rjags", "infercnv", "copykat", "GenomicRanges", "mixtools", "parallelDist")
message("Verifying package loading")
for (package in required) {
  suppressPackageStartupMessages(library(package, character.only = TRUE))
  message("  ", package, " ", as.character(utils::packageVersion(package)))
}

# JAGS must be reachable now, not first discovered inside a Slurm job.
jags_version <- rjags::jags.version()
if (!length(jags_version) || !nzchar(as.character(jags_version))) {
  stop("rjags cannot reach the JAGS library")
}
message("  JAGS ", as.character(jags_version))

versions <- rbind(
  data.frame(package = required,
             version = vapply(required, function(p) as.character(utils::packageVersion(p)),
                              character(1)),
             stringsAsFactors = FALSE),
  data.frame(package = c("R", "Bioconductor", "JAGS", "copykat_commit"),
             version = c(paste(R.version$major, R.version$minor, sep = "."),
                         as.character(BiocManager::version()),
                         as.character(jags_version),
                         copykat_commit),
             stringsAsFactors = FALSE)
)
dir.create("/opt/pitnets-cnv", recursive = TRUE, showWarnings = FALSE)
write.table(versions, "/opt/pitnets-cnv/r-package-versions.tsv",
            sep = "\t", quote = FALSE, row.names = FALSE)
message("All copy-number R packages installed and loadable")
