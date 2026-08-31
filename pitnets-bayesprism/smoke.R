#!/usr/bin/env Rscript

# Smoke test for the PitNET deconvolution image.
#
# CI mounts this file into the container and runs it with --network none. It
# must print a line beginning with "smoke ok:" for the build to pass.

expected_version <- Sys.getenv("BAYESPRISM_VERSION", "2.2.3")

fail <- function(msg) {
  cat("smoke FAILED:", msg, "\n")
  quit(status = 1L)
}

suppressPackageStartupMessages(library(BayesPrism))
version <- as.character(packageVersion("BayesPrism"))
if (version != expected_version) {
  fail(paste("BayesPrism version", version, "!=", expected_version))
}

for (package in c("snowfall", "gplots", "scran", "BiocParallel", "NMF", "Matrix")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    fail(paste("missing package", package))
  }
}

for (fn in c("new.prism", "run.prism", "posterior.cell.type", "posterior.cs", "get.exp")) {
  if (!exists(fn, where = asNamespace("BayesPrism"), mode = "function")) {
    fail(paste("BayesPrism function not found:", fn))
  }
}

# Minimal end-to-end exercise of the core estimation path on synthetic data:
# two cell types, forty genes, three bulk samples. This checks that the
# optimizer and its dependencies actually run, not just that they load.
set.seed(20260830)
n_genes <- 40L
profile_a <- c(rep(8, 20), rep(1, 20))
profile_b <- c(rep(1, 20), rep(8, 20))
gene_names <- paste0("ENSG", sprintf("%011d", seq_len(n_genes)))
cell_names <- paste0("cell", 1:20)

counts <- matrix(0L, n_genes, 20, dimnames = list(gene_names, cell_names))
counts[, 1:10] <- t(replicate(n_genes, rpois(10, profile_a)))
counts[, 11:20] <- t(replicate(n_genes, rpois(10, profile_b)))
sc_ref <- Matrix::Matrix(counts, sparse = TRUE)

type_labels <- rep(c("typeA", "typeB"), each = 10)
state_labels <- rep(c("A_donor1", "A_donor2", "B_donor1", "B_donor2"), each = 5)

bulk <- matrix(0L, n_genes, 3, dimnames = list(gene_names, c("s1", "s2", "s3")))
bulk[, 1] <- rpois(n_genes, 4 * profile_a + 1 * profile_b)
bulk[, 2] <- rpois(n_genes, 2 * profile_a + 3 * profile_b)
bulk[, 3] <- rpois(n_genes, 1 * profile_a + 5 * profile_b)
bulk_mat <- Matrix::Matrix(bulk, sparse = TRUE)

prism <- new.prism(
  reference = sc_ref,
  mixture = bulk_mat,
  input.type = "count.matrix",
  cell.type.labels = type_labels,
  cell.state.labels = state_labels,
  key = "smoke",
  out.dir = file.path(tempdir(), "smoke_prism"),
  n.cores = 1
)

result <- run.prism(prism, n.cores = 1)

fractions <- posterior.cell.type(result)
if (is.null(fractions) || nrow(fractions) != 3L || ncol(fractions) != 2L) {
  fail("unexpected posterior cell type dimensions")
}
if (any(abs(rowSums(fractions) - 1) > 1e-6)) {
  fail("posterior cell type fractions do not sum to 1")
}
# Sample 1 is mostly typeA, sample 3 mostly typeB; require the ordering to hold.
if (!(fractions[1, "typeA"] > fractions[3, "typeA"])) {
  fail("fraction ordering does not follow the constructed mixture")
}

unlink(file.path(tempdir(), "smoke_prism"), recursive = TRUE)
cat("smoke ok: BayesPrism", version, "end-to-end deconvolution on synthetic data\n")
