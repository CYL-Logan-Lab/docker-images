# R0 uses CRAN coloc 6.0.1 and regression-tests the behavior documented at
# commit 50fe5291fea7f8ab49823bd86747385d6e56870f. No R1-R9 packages belong here.
stopifnot(getRversion() == "4.5.2")

cran_repo <- Sys.getenv("R0_CRAN_REPO")
stopifnot(nzchar(cran_repo))
options(repos = c(CRAN = cran_repo), Ncpus = 4L)

PKG_PINNED <- c(
  data.table  = "1.18.4",
  ggplot2     = "4.0.3",
  viridis     = "0.6.5",
  matrixStats = "1.5.0",
  susieR      = "0.14.2",
  digest      = "0.6.39",
  coloc       = "6.0.1"
)

utils::install.packages(names(PKG_PINNED), dependencies = NA)

got <- vapply(names(PKG_PINNED), function(package) {
  tryCatch(as.character(utils::packageVersion(package)),
           error = function(error) NA_character_)
}, character(1))
bad <- is.na(got) | got != PKG_PINNED
if (any(bad)) {
  stop(
    "package versions disagree with the frozen R0 recipe:\n",
    paste(sprintf("  %-12s expected %-8s got %s",
                  names(PKG_PINNED)[bad], PKG_PINNED[bad],
                  ifelse(is.na(got[bad]), "<not installed>", got[bad])),
          collapse = "\n")
  )
}

invisible(lapply(names(PKG_PINNED), function(package) {
  library(package, character.only = TRUE, quietly = TRUE)
}))

coloc_bf_bf <- get("coloc.bf_bf", envir = loadNamespace("coloc"))
stopifnot(
  is.function(coloc_bf_bf),
  identical(names(formals(coloc_bf_bf)),
            c("bf1", "bf2", "p1", "p2", "p12", "overlap.min",
              "trim_by_posterior", "prior_weights1", "prior_weights2"))
)

installed <- utils::installed.packages()[, c("Package", "Version", "LibPath"), drop = FALSE]
installed <- installed[order(installed[, "Package"]), , drop = FALSE]
writeLines(
  c(
    "# Complete R package manifest for t2d-meta-lipid",
    paste0("# R: ", R.version.string),
    paste0("# CRAN: ", cran_repo),
    "package\tversion\tlibpath",
    apply(installed, 1L, paste, collapse = "\t")
  ),
  "/opt/Renv-manifest.tsv"
)
