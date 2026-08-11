# Smoke test for the t2d-sc-lipid image. Run by .github/workflows/build.yml
# against the image that build just produced, with --network none.
#
# It lives here as a file rather than inside the workflow's `docker run ...
# Rscript -e '...'` because that form silently stopped working. Rscript does not
# hand the expression to R verbatim: it encodes it, replacing every space with
# "~+~" and every newline with "~n~", and the *encoded* string has to fit in a
# 10000-character buffer. The former workflow payload -- the same R code as
# below, indented two more spaces inside the YAML -- was 7846 characters with
# 1434 spaces and 134 newlines, which encodes to 10982. Over the limit, Rscript
# prints "WARNING: '-e ...'", drops the expression, and starts R with no input;
# R reads EOF on stdin and **exits 0**. The CI step went green in 0.3 seconds
# having run none of the assertions below.
#
# Reproduce the limit in one line, on any image here (3320 prints RAN, 3340
# prints the warning and exits 0 -- so the cliff is between 9973 and 10033
# encoded characters):
#
#   Rscript --vanilla -e "$(python3 -c "print('cat(\"RAN\\n\")' + ' '*3340)")"
#
# The version of this that mattered: it was the growth of the file that broke
# it. The v3 payload encoded to 3035 and really did run (77 s, "smoke ok:" in
# the log). Nothing about the failure was visible in a diff of the assertions.
#
# It is mounted at run time and deliberately NOT copied into the image: as a
# Dockerfile layer it would be skipped on a cache hit, and the build would look
# verified without having started an R process.
#
# The last line prints a sentinel beginning "smoke ok:". The workflow greps for
# it. Exit 0 is not enough evidence that this file ran -- that is exactly the
# failure above.

suppressPackageStartupMessages({
  library(Seurat); library(scDblFinder)
  library(clusterProfiler); library(org.Hs.eg.db); library(ReactomePA)
  library(CellChat); library(nichenetr)
})
stopifnot(file.exists("/opt/Renv-manifest.tsv"))
# --network none is the point of this line: enrichment must work with
# no network at all, otherwise the gene sets are not really in the image.
# Each of the three back-ends is exercised separately -- they read
# different databases (org.Hs.eg.db, reactome.db) and a working GO
# query says nothing about whether reactome.db shipped intact.
eg <- suppressMessages(bitr(c("POSTN","COL1A1","COL3A1","COL6A1","COL5A1",
                              "DCN","LUM","FN1","FBN1","SPARC","TGFB1","MMP2"),
                            "SYMBOL", "ENTREZID", org.Hs.eg.db))
go <- enrichGO(eg$ENTREZID, OrgDb = org.Hs.eg.db, ont = "BP",
               pvalueCutoff = 0.05, readable = TRUE)
re <- ReactomePA::enrichPathway(eg$ENTREZID, pvalueCutoff = 0.05, readable = TRUE)
stopifnot(nrow(as.data.frame(go)) > 0, nrow(as.data.frame(re)) > 0)
# enrichplot is only ever used to draw; building the plot object is
# what catches a broken install, so build one and throw it away.
invisible(ggplot2::ggplot_build(enrichplot::dotplot(go, showCategory = 5)))
# fgsea needs a ranked vector rather than a gene list, so give it one,
# and a gene set that is a strict subset of it -- a set equal to the
# whole ranking is degenerate and would pass without testing anything.
# fgseaSimple by name: the permutation path reached via fgsea(nperm=)
# is deprecated and a deprecation warning here would be noise.
set.seed(1)
rk <- setNames(seq(2, -2, length.out = length(eg$ENTREZID)), eg$ENTREZID)
fg <- fgsea::fgseaSimple(list(top = eg$ENTREZID[1:5]), rk, minSize = 2, nperm = 200)
stopifnot(nrow(fg) == 1, is.finite(fg$ES))
# ---- cell-cell communication stack, all of it under --network none ----
# CellChatDB ships inside the package; this is what verifies that claim.
db <- CellChatDB.human$interaction
stopifnot(is.data.frame(db), nrow(db) > 0,
          all(c("SPP1", "CSF1", "PDGFA") %in% db$ligand))
# A loadable CellChat says nothing about whether inference runs, and that
# is where a broken build actually shows. So run the whole chain on a toy
# object built to have a known answer -- group A carries the ligands, B the
# receptors, so A -> B must come out non-empty. (computeCommunProb at the
# pinned commit is R over Matrix::crossprod, not the package's Rcpp code;
# the Rcpp routine is ComputeSNN and this path never reaches it. What this
# exercises is the inference chain, not the native layer.)
# The genes that carry the signal are fixed by name; the 200 background
# genes come from the DB so that database subsetting and the
# over-expression selection have a real set to work on. filterCommunication
# is only walked through, not exercised: min.cells = 10 against two groups
# of 40 can never drop anything, which is deliberate -- a toy object whose
# groups got filtered away would assert nothing.
set.seed(1)
lig <- c("SPP1", "CSF1", "TGFB1", "PDGFA")
rec <- c("CD44", "CSF1R", "TGFBR1", "TGFBR2", "PDGFRA", "PDGFRB")
fil <- setdiff(unique(c(db$ligand, db$receptor)), c(lig, rec))
genes <- c(lig, rec, grep("_", fil, invert = TRUE, value = TRUE)[1:200])
n <- 40L
m <- matrix(rpois(length(genes) * 2L * n, lambda = 2), nrow = length(genes),
            dimnames = list(genes, paste0("c", seq_len(2L * n))))
m[lig, seq_len(n)] <- m[lig, seq_len(n)] + 60L
m[rec, -seq_len(n)] <- m[rec, -seq_len(n)] + 60L
dat <- log1p(sweep(m, 2, colSums(m), "/") * 1e4)
meta <- data.frame(labels = factor(rep(c("A", "B"), each = n)),
                   row.names = colnames(m))
cc <- createCellChat(object = dat, meta = meta, group.by = "labels")
cc@DB <- CellChatDB.human
cc <- subsetData(cc)
cc <- identifyOverExpressedGenes(cc, thresh.p = 1)
cc <- identifyOverExpressedInteractions(cc)
cc <- computeCommunProb(cc, type = "truncatedMean", trim = 0.1)
cc <- filterCommunication(cc, min.cells = 10)
cc <- aggregateNet(cc)
net <- cc@net$count
stopifnot(is.matrix(net), identical(dim(net), c(2L, 2L)),
          net["A", "B"] > 0, nrow(subsetCommunication(cc)) > 0)
# NicheNet priors are the one database not shipped by its package, so
# they were baked in by the Dockerfile. Read from the env var the image
# sets rather than a literal path: a missing ENV then fails here too.
prior <- Sys.getenv("NICHENET_PRIOR_DIR")
stopifnot(nzchar(prior))
ltm <- readRDS(file.path(prior, "ligand_target_matrix_nsga2r_final.rds"))
# Orientation is targets x ligands. Asserting only that ligands are in
# colnames would not catch a transposed matrix -- ligands are genes and
# so appear in both margins. Targets appearing in rownames but NOT all
# in colnames is the pair of checks that pins it.
stopifnot(is.matrix(ltm), nrow(ltm) > 1e4, ncol(ltm) > 1e3,
          all(c("SPP1", "CSF1", "TGFB1") %in% colnames(ltm)),
          all(c("CD44", "CSF1R", "COL1A1") %in% rownames(ltm)),
          !all(c("CD44", "CSF1R", "COL1A1") %in% colnames(ltm)),
          min(ltm[, "SPP1"]) >= 0)
lr <- readRDS(file.path(prior, "lr_network_human_21122021.rds"))
stopifnot(is.data.frame(lr), nrow(lr) > 0,
          all(c("from", "to") %in% colnames(lr)),
          any(lr$from == "SPP1" & lr$to == "CD44"),
          any(lr$from == "CSF1" & lr$to == "CSF1R"))
# Reading the priors is not the same as nichenetr being able to use
# them, so call the function the downstream step will call, on a
# question whose answer is fixed by construction: background = the
# 2000 highest-scoring targets of SPP1, geneset = the top 100 of
# those. SPP1 then separates the geneset perfectly, so its AUROC is
# exactly 1 -- provided score[100] is strictly above score[101],
# which is asserted rather than assumed because a tie at that
# boundary is the one thing that would break the equality.
#
# AUROC and not pearson because only AUROC has a value this
# construction *derives*. A perfect separation is exactly 1, and the
# assertion is that equality. Pearson against the binary membership
# vector is the point-biserial correlation, which does have a closed
# form -- but one in the score magnitudes, not in the ordering, so
# this construction fixes no value for it. Any number asserted for
# pearson would have had to be read off a run rather than reasoned
# to, and a check whose expected value came out of the thing it is
# checking is the failure mode this whole file exists to talk about.
#
# The inputs are deterministic: background and geneset are fixed
# slices of one sorted column, not a random draw. An earlier version
# drew them at random and justified it as "the property holds for any
# subset", which is false -- the perfect separation is a property of
# taking the geneset from SPP1's own ranking, so off that construction
# AUROC 1 is no longer guaranteed and another candidate can win.
# nichenetr does call sample() further in (calculate_auc_iregulon),
# but only for the iRegulon columns, which are not read here; the
# returned auroc is the same on repeated calls. So this is
# reproducible without seeding it, and no seed is set for it.
cand <- intersect(c("SPP1", "CSF1", "TGFB1", "PDGFA", "IL34", "GAS6",
                    "CXCL12", "APOE", "FN1", "IL6", "TNF"), colnames(ltm))
sc <- sort(ltm[, "SPP1"], decreasing = TRUE)
stopifnot(length(cand) > 5, sc[[100]] > sc[[101]])
bg <- names(sc)[1:2000]
gs <- names(sc)[1:100]
act <- nichenetr::predict_ligand_activities(
  geneset = gs, background_expressed_genes = bg,
  ligand_target_matrix = ltm[bg, cand, drop = FALSE],
  potential_ligands = cand)
au <- setNames(act$auroc, act$test_ligand)
stopifnot(nrow(act) == length(cand), all(is.finite(au)),
          identical(sort(names(au)), sort(cand)),
          au[["SPP1"]] == 1, sum(au >= au[["SPP1"]]) == 1L)
cat("smoke ok:", R.version.string,
    "/ Seurat", as.character(packageVersion("Seurat")),
    "/ scDblFinder", as.character(packageVersion("scDblFinder")),
    "/ clusterProfiler", as.character(packageVersion("clusterProfiler")),
    "/ offline enrichGO", nrow(as.data.frame(go)), "terms",
    "/ enrichPathway", nrow(as.data.frame(re)), "pathways",
    "/ CellChat", as.character(packageVersion("CellChat")),
    "with", nrow(db), "interactions, toy A->B", net["A", "B"],
    "/ nichenetr", as.character(packageVersion("nichenetr")),
    "priors", nrow(ltm), "targets x", ncol(ltm), "ligands,",
    nrow(lr), "LR pairs, SPP1 auroc", au[["SPP1"]],
    "vs runner-up", round(max(au[names(au) != "SPP1"]), 4), "\n")
