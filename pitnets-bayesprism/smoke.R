#!/usr/bin/env Rscript

# Smoke test for the PitNET deconvolution image.
#
# CI mounts this file into the container and runs it with --network none. It
# must print a line beginning with "smoke ok:" for the build to pass.
#
# The API calls below were written against the BayesPrism 2.2.3 source at the
# pinned commit, not against documentation prose:
#   new.prism takes reference as cells-by-genes and mixture as samples-by-genes,
#   has no out.dir or n.cores argument, and `key` names the malignant cell type
#   that triggers the tumour-specific update mechanism.
#   run.prism returns a BayesPrism object; fractions are extracted with
#   get.fraction, which returns a samples-by-types matrix.

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

# The CRAN repository must be a dated Posit snapshot. A rolling mirror here
# would let the same Dockerfile install different packages over time. The
# Dockerfile writes this into Rprofile.site, so it applies at run time too.
repo <- getOption("repos")[["CRAN"]]
if (is.null(repo) || !grepl("packagemanager.posit.co/cran/.*/[0-9]{4}-[0-9]{2}-[0-9]{2}", repo)) {
  fail(paste("CRAN repo is not a dated snapshot:", if (is.null(repo)) "NULL" else repo))
}

# Minimal end-to-end exercise of the estimation path on synthetic data: two
# cell types with disjoint expression programs, each split into two donor
# states, three bulk samples of known mixing. Checks that the optimizer and
# its dependencies run and that recovered fractions follow the mixture.
set.seed(20260830)
n_genes <- 40L
profile_a <- c(rep(8, 20), rep(1, 20))
profile_b <- c(rep(1, 20), rep(8, 20))
gene_names <- paste0("ENSG", sprintf("%011d", seq_len(n_genes)))
cell_names <- paste0("cell", 1:20)

# reference: cells-by-genes, as the package expects.
counts <- matrix(0L, 20, n_genes, dimnames = list(cell_names, gene_names))
counts[1:10, ] <- t(replicate(10, rpois(n_genes, profile_a)))
counts[11:20, ] <- t(replicate(10, rpois(n_genes, profile_b)))
sc_ref <- Matrix::Matrix(counts, sparse = TRUE)

type_labels <- rep(c("typeA", "typeB"), each = 10)
state_labels <- rep(c("A_donor1", "A_donor2", "B_donor1", "B_donor2"), each = 5)

# mixture: samples-by-genes.
bulk <- matrix(0L, 3, n_genes, dimnames = list(c("s1", "s2", "s3"), gene_names))
bulk[1, ] <- rpois(n_genes, 4 * profile_a + 1 * profile_b)
bulk[2, ] <- rpois(n_genes, 2 * profile_a + 3 * profile_b)
bulk[3, ] <- rpois(n_genes, 1 * profile_a + 5 * profile_b)
bulk_mat <- Matrix::Matrix(bulk, sparse = TRUE)

prism <- new.prism(
  reference = sc_ref,
  mixture = bulk_mat,
  input.type = "count.matrix",
  cell.type.labels = type_labels,
  cell.state.labels = state_labels,
  key = "typeA"
)

result <- run.prism(prism, n.cores = 1)

fractions <- get.fraction(result, which.theta = "final", state.or.type = "type")
if (is.null(fractions) || nrow(fractions) != 3L || ncol(fractions) != 2L) {
  fail(paste("unexpected fraction matrix dims:",
             paste(dim(fractions), collapse = "x")))
}
if (any(abs(rowSums(fractions) - 1) > 1e-6)) {
  fail("fractions do not sum to 1")
}
if (!(fractions["s1", "typeA"] > fractions["s3", "typeA"])) {
  fail("fraction ordering does not follow the constructed mixture")
}

state_fractions <- get.fraction(result, which.theta = "final", state.or.type = "state")
if (is.null(state_fractions) || ncol(state_fractions) != 4L) {
  fail("unexpected state fraction matrix")
}
if (any(abs(rowSums(state_fractions) - 1) > 1e-6)) {
  fail("state fractions do not sum to 1")
}

exp_a <- get.exp(result, state.or.type = "type", cell.name = "typeA")
if (is.null(exp_a) || ncol(exp_a) != n_genes) {
  fail("unexpected recovered expression matrix")
}

cat("smoke ok: BayesPrism", version, "end-to-end deconvolution on synthetic data\n")
