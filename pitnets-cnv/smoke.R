#!/usr/bin/env Rscript

# Smoke test for the copy-number image, mounted read-only at /smoke by CI and
# run with `--network none`. Every check therefore has to be self-contained.
#
# The final line must start with "smoke ok:" -- CI greps for that sentinel
# because an R process can exit 0 without having executed anything.

suppressPackageStartupMessages({
  library(rjags)
  library(infercnv)
  library(CaSpER)
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

# 3. CaSpER must expose the entry points the analysis calls.
check("CaSpER exports its entry points", {
  exported <- getNamespaceExports("CaSpER")
  missing <- setdiff(c("CreateCasperObject", "runCaSpER"), exported)
  if (length(missing)) stop("missing exports: ", paste(missing, collapse = ", "))
  message("    CaSpER exports ", length(exported), " functions")
})

# 4. CaSpER's compiled HMM must be loaded, not merely present on disk.
check("CaSpER compiled HMM is loaded", {
  if (!"CaSpER" %in% names(getLoadedDLLs())) stop("CaSpER DLL is not loaded")
})

# 5. BAFExtract must be callable. It has no cell-barcode awareness, so the
#    analysis stage splits BAMs by barcode group before piping into it; this only
#    verifies the binary exists and runs.
check("BAFExtract binary runs", {
  path <- Sys.which("BAFExtract")
  if (!nzchar(path)) stop("BAFExtract not found on PATH")
  output <- suppressWarnings(system2("BAFExtract", stdout = TRUE, stderr = TRUE))
  if (!length(output)) stop("BAFExtract produced no output")
  message("    ", path)
})

# 6. The base image's analysis stack must still be intact: this image is a
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

cat(sprintf("smoke ok: pitnets-cnv | R %s.%s | infercnv %s | CaSpER %s | JAGS %s\n",
            R.version$major, R.version$minor,
            as.character(utils::packageVersion("infercnv")),
            as.character(utils::packageVersion("CaSpER")),
            as.character(rjags::jags.version())))
