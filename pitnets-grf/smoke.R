suppressPackageStartupMessages({
  library(Seurat)
  library(SpatialExperiment)
  library(DESeq2)
  library(IsoformSwitchAnalyzeR)
  library(DRIMSeq)
  library(GenomicRanges)
  library(ComplexHeatmap)
  library(ggplot2)
  library(patchwork)
})

stopifnot(
  getRversion() == "4.5.2",
  packageVersion("Seurat") == "5.5.1",
  file.exists("/opt/Renv-manifest.tsv"),
  file.exists("/opt/pitnets-pyenv-manifest.tsv")
)

set.seed(7)
single_cell_counts <- matrix(rpois(40 * 24, 4), nrow = 40,
                             dimnames = list(paste0("gene", seq_len(40)),
                                             paste0("cell", seq_len(24))))
seurat <- CreateSeuratObject(single_cell_counts, min.cells = 0, min.features = 0)
seurat <- NormalizeData(seurat, verbose = FALSE)
seurat <- FindVariableFeatures(seurat, nfeatures = 15, verbose = FALSE)
stopifnot(ncol(seurat) == 24, length(VariableFeatures(seurat)) == 15)

spatial <- SpatialExperiment(
  assays = list(counts = single_cell_counts),
  spatialCoords = cbind(x = rep(seq_len(6), each = 4), y = rep(seq_len(4), 6))
)
stopifnot(ncol(spatial) == 24, ncol(spatialCoords(spatial)) == 2)

bulk_counts <- matrix(rnbinom(100 * 8, mu = 60, size = 4), nrow = 100,
                      dimnames = list(paste0("gene", seq_len(100)),
                                      paste0("sample", seq_len(8))))
condition <- factor(rep(c("control", "tumour"), each = 4))
bulk_metadata <- data.frame(condition, row.names = colnames(bulk_counts))
dds <- DESeqDataSetFromMatrix(bulk_counts, bulk_metadata, ~condition)
dds <- DESeq(dds, quiet = TRUE)
bulk_result <- DESeq2::results(dds)
stopifnot(nrow(bulk_result) == 100, "log2FoldChange" %in% colnames(bulk_result))

ranges <- GRanges(c("chr1", "chr1"), IRanges(c(100, 180), width = 100))
stopifnot(length(findOverlaps(ranges, ranges)) >= 2)

drs_counts <- data.frame(
  gene_id = c("gene1", "gene1", "gene2", "gene2"),
  feature_id = c("tx1", "tx2", "tx3", "tx4"),
  P1 = c(12, 5, 9, 3),
  P2 = c(10, 7, 11, 4)
)
drim <- dmDSdata(counts = drs_counts, samples = data.frame(
  sample_id = c("P1", "P2"), group = c("control", "tumour")
))
stopifnot(inherits(drim, "dmDSdata"), nrow(counts(drim)) == 4)

pdf_file <- tempfile(fileext = ".pdf")
grDevices::pdf(pdf_file)
print(ggplot(data.frame(x = 1:5, y = c(1, 4, 2, 5, 3)), aes(x, y)) +
        geom_line() + theme_classic())
ComplexHeatmap::draw(Heatmap(matrix(rnorm(25), 5), name = "z"))
grDevices::dev.off()
stopifnot(file.info(pdf_file)$size > 0)

python <- "/opt/pitnets-pyenv/bin/python"
python_smoke <- "/smoke/smoke.py"
stopifnot(file.exists(python), file.exists(python_smoke))
status <- system2(python, c("-B", python_smoke))
stopifnot(status == 0)

cat(
  "smoke ok: PitNETs scRNA-seq/ST/bulk/DRS downstream analysis and graphics; ",
  "R ", getRversion(), ", Seurat ", packageVersion("Seurat"),
  ", DESeq2 ", packageVersion("DESeq2"),
  ", IsoformSwitchAnalyzeR ", packageVersion("IsoformSwitchAnalyzeR"), "\n",
  sep = ""
)
