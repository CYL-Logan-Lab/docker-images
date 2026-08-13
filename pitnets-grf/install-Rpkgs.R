# Additional R packages for processed PitNET multi-omics results.
# CRAN is frozen to a dated Posit Package Manager snapshot. Bioconductor is
# fixed to release 3.22; every package called directly is version-asserted.
stopifnot(
  getRversion() == "4.5.2",
  utils::packageVersion("Seurat") == "5.5.1"
)

options(
  repos = c(
    BIOC = "https://bioconductor.org/packages/3.22/bioc",
    BIOCANN = "https://bioconductor.org/packages/3.22/data/annotation",
    BIOCEXP = "https://bioconductor.org/packages/3.22/data/experiment",
    CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/2026-08-06"
  ),
  timeout = 1800,
  Ncpus = max(1L, parallel::detectCores(logical = FALSE))
)

PKG_PINNED <- c(
  # Spatial and single-cell result containers/statistics.
  SpatialExperiment     = "1.20.0",
  SingleCellExperiment  = "1.32.0",
  scuttle               = "1.20.0",
  scran                  = "1.38.1",
  scater                 = "1.38.1",

  # Bulk RNA-seq differential expression and cross-cohort modelling.
  edgeR                  = "4.8.2",
  limma                  = "3.66.0",
  DESeq2                 = "1.50.2",
  tximport               = "1.38.2",
  sva                    = "3.58.0",
  variancePartition      = "1.40.2",
  GSVA                   = "2.4.9",

  # Nanopore DRS result-level isoform and differential-usage analysis.
  IsoformSwitchAnalyzeR  = "2.10.0",
  DEXSeq                 = "1.56.0",
  DRIMSeq                = "1.38.0",
  stageR                 = "1.32.0",

  # Transcript annotations, genomic intervals and alignment result access.
  GenomicRanges          = "1.62.1",
  GenomicFeatures        = "1.62.0",
  rtracklayer            = "1.70.1",
  Rsamtools              = "2.26.0",
  Biostrings             = "2.78.0",

  # Publication graphics and common result tables.
  ComplexHeatmap         = "2.26.1",
  circlize               = "0.4.18",
  ggplot2                = "4.0.3",
  patchwork              = "1.3.2",
  cowplot                = "1.2.0",
  ggrepel                = "0.9.8",
  ggnewscale             = "0.5.2",
  ggalluvial             = "0.12.6",
  pheatmap               = "1.0.13",
  viridis                = "0.6.5",
  svglite                = "2.2.2",
  ragg                   = "1.5.2",
  data.table             = "1.18.4",
  readr                  = "2.2.0",
  readxl                 = "1.5.0",
  openxlsx               = "4.2.8.1",
  arrow                  = "25.0.0"
)

installed <- vapply(names(PKG_PINNED), function(package) {
  tryCatch(as.character(utils::packageVersion(package)),
           error = function(error) NA_character_)
}, character(1))
needs_install <- is.na(installed) |
  numeric_version(ifelse(is.na(installed), "0", installed)) !=
  numeric_version(PKG_PINNED)

if (any(needs_install)) {
  install.packages(names(PKG_PINNED)[needs_install])
}

installed <- vapply(names(PKG_PINNED), function(package) {
  tryCatch(as.character(utils::packageVersion(package)),
           error = function(error) NA_character_)
}, character(1))
present <- !is.na(installed)
bad <- !present
bad[present] <- numeric_version(installed[present]) !=
  numeric_version(PKG_PINNED[present])
if (any(bad)) {
  stop(
    "package versions disagree with install-Rpkgs.R:\n",
    paste(sprintf("  %-24s expected %-10s got %s",
                  names(PKG_PINNED)[bad], PKG_PINNED[bad],
                  ifelse(is.na(installed[bad]), "<not installed>", installed[bad])),
          collapse = "\n"),
    "\nUpdate the pins; do not remove this assertion."
  )
}

invisible(lapply(names(PKG_PINNED), loadNamespace))

manifest <- data.frame(
  package = sort(unique(c(.packages(all.available = TRUE), names(PKG_PINNED)))),
  stringsAsFactors = FALSE
)
manifest$version <- vapply(manifest$package, function(package) {
  tryCatch(as.character(utils::packageVersion(package)),
           error = function(error) NA_character_)
}, character(1))
manifest <- manifest[!is.na(manifest$version), , drop = FALSE]
utils::write.table(manifest, "/opt/Renv-manifest.tsv", sep = "\t",
                   quote = FALSE, row.names = FALSE)

message("pitnets-grf R layer intact: ", length(PKG_PINNED),
        " direct package versions asserted")
