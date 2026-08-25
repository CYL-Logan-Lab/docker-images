#!/usr/bin/env Rscript

# Smoke test for the copy-number image, mounted read-only at /smoke by CI and
# run with `--network none`. Every check therefore has to be self-contained.
#
# The final line must start with "smoke ok:" -- CI greps for that sentinel
# because an R process can exit 0 without having executed anything.

suppressPackageStartupMessages({
  library(rjags)
  library(infercnv)
  library(copykat)
  library(Matrix)
})

options(warn = 1)

failures <- character(0)
check <- function(label, expression) {
  ok <- tryCatch({ force(expression); TRUE }, error = function(e) {
    failures <<- c(failures, paste0(label, ": ", conditionMessage(e)))
    FALSE
  })
  message(sprintf("  %-46s %s", label, if (ok) "ok" else "FAILED"))
  invisible(ok)
}

message("pitnets-cnv smoke test")
message("  ", R.version.string)

# 1. inferCNV needs JAGS through rjags for its HMM step.
check("rjags reaches the JAGS library", {
  version <- rjags::jags.version()
  if (!length(version) || !nzchar(as.character(version))) stop("no JAGS version reported")
  message("    JAGS ", as.character(version))
})

# 2. inferCNV object construction with a reference group, which is the exact
#    call the analysis stage makes.
check("inferCNV builds an object with a reference", {
  set.seed(1)
  genes <- sprintf("GENE%03d", 1:120)
  cells <- c(sprintf("tumor%02d", 1:40), sprintf("ref%02d", 1:40))
  counts <- matrix(rpois(length(genes) * length(cells), 12),
                   nrow = length(genes), dimnames = list(genes, cells))
  counts[1:40, 1:40] <- counts[1:40, 1:40] * 2L

  work <- file.path(tempdir(), "infercnv-smoke")
  dir.create(work, recursive = TRUE, showWarnings = FALSE)

  annotation_file <- file.path(work, "annotations.tsv")
  write.table(data.frame(group = c(rep("tumor", 40), rep("reference", 40)), row.names = cells),
              annotation_file, sep = "\t", quote = FALSE, col.names = FALSE)

  order_file <- file.path(work, "gene_order.tsv")
  write.table(data.frame(gene = genes,
                         chr = rep(c("chr1", "chr2", "chr3"), each = 40),
                         start = rep(seq(1, by = 1000, length.out = 40), times = 3),
                         stop = rep(seq(900, by = 1000, length.out = 40), times = 3)),
              order_file, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

  object <- infercnv::CreateInfercnvObject(
    raw_counts_matrix = counts,
    annotations_file = annotation_file,
    gene_order_file = order_file,
    ref_group_names = "reference",
    delim = "\t"
  )
  if (ncol(object@expr.data) != length(cells)) stop("unexpected cell count")
  if (!length(object@reference_grouped_cell_indices)) stop("reference group not registered")
})

# 3. copyKAT must expose its entry point and its declared imports must load,
#    since those are what break first on a dependency drift.
check("copyKAT entry point and imports are available", {
  exported <- getNamespaceExports("copykat")
  if (!"copykat" %in% exported) stop("copykat() is not exported")
  for (package in c("parallelDist", "dlm", "mixtools", "cluster", "MCMCpack", "transport")) {
    if (!requireNamespace(package, quietly = TRUE)) stop("missing import: ", package)
  }
  message("    copykat ", as.character(utils::packageVersion("copykat")),
          " exports ", length(exported), " functions")
})

# 4. The mixture and distance machinery copyKAT relies on must actually run,
#    not merely be importable.
check("copyKAT numeric machinery runs", {
  set.seed(2)
  values <- c(rnorm(200, 0, 1), rnorm(200, 4, 1))
  fit <- suppressMessages(mixtools::normalmixEM(values, k = 2, maxit = 200, epsilon = 1e-3))
  if (length(fit$mu) != 2) stop("mixture model did not return two components")
  distance <- parallelDist::parDist(matrix(rnorm(200), nrow = 20), method = "euclidean")
  if (!inherits(distance, "dist")) stop("parallelDist did not return a dist object")
})

# 5. The base image's analysis stack must still be intact: this image is a
#    superset, and a regression here would silently change tumour results.
check("base analysis stack is unchanged", {
  for (package in c("Seurat", "UCell", "RcppML", "presto")) {
    suppressPackageStartupMessages(library(package, character.only = TRUE))
  }
  if (utils::packageVersion("Seurat") < "5.0.0") stop("unexpected Seurat version")
  message("    Seurat ", as.character(utils::packageVersion("Seurat")),
          ", UCell ", as.character(utils::packageVersion("UCell")),
          ", RcppML ", as.character(utils::packageVersion("RcppML")))
})

if (length(failures)) {
  message("\nFAILED:")
  for (failure in failures) message("  - ", failure)
  quit(status = 1)
}

cat(sprintf("smoke ok: pitnets-cnv | R %s.%s | infercnv %s | copykat %s | JAGS %s\n",
            R.version$major, R.version$minor,
            as.character(utils::packageVersion("infercnv")),
            as.character(utils::packageVersion("copykat")),
            as.character(rjags::jags.version())))
