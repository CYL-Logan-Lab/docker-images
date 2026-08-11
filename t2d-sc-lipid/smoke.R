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
  library(WGCNA); library(hdWGCNA); library(UCell); library(GSVA)
  library(decoupleR); library(slingshot)
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
# ---- gene-program stack (v5), all of it under --network none ----
# hdWGCNA Depends on enrichR, whose .onAttach issues six untimed httr::GET
# requests to maayanlab.cloud. This file is the only place in the build that
# attaches it -- the two installers deliberately loadNamespace() instead,
# because they run with network and this step does not. The library() call at
# the top of this file is therefore both the only attach test and a safe one:
# with no network, attaching must still succeed, and it does because
# has_internet() is false and enrichR falls back to
# options(enrichR.live = FALSE) and carries on. That value is printed in
# the sentinel rather than asserted, deliberately -- which branch enrichR takes
# depends on curl::has_internet() and on options its own .onAttach set moments
# earlier, so an assertion either way would be a claim about enrichR's internals
# rather than about this image. Nothing downstream is allowed to route
# enrichment through it; the databases clusterProfiler queries above are the
# ones this project uses, and they are on disk.
#
# WGCNA first, on a matrix whose answer is fixed by construction: two blocks of
# 25 genes driven by two independent latent variables, plus 50 genes that are
# noise. Module detection has to put each block together and keep the two apart.
# This is asserted separately from the hdWGCNA run below on purpose -- when it
# breaks, the two together say whether it was the engine or the single-cell
# wrapper, which one combined test could not.
set.seed(42)
ns <- 60L; nb <- 25L; nn <- 50L
blk <- function(lat) vapply(seq_len(nb), function(i) lat + rnorm(ns, sd = 0.35),
                            numeric(ns))
wdat <- cbind(blk(rnorm(ns)), blk(rnorm(ns)), matrix(rnorm(ns * nn), ns, nn))
colnames(wdat) <- c(paste0("A", 1:nb), paste0("B", 1:nb), paste0("N", 1:nn))
wnet <- blockwiseModules(wdat, power = 6, networkType = "signed",
                         minModuleSize = 10, numericLabels = TRUE, verbose = 0)
wm <- setNames(wnet$colors, colnames(wdat))
# numericLabels = TRUE makes the unassigned module 0, so "!= 0" is "not grey".
stopifnot(length(unique(wm[paste0("A", 1:nb)])) == 1L,
          length(unique(wm[paste0("B", 1:nb)])) == 1L,
          wm[["A1"]] != 0, wm[["B1"]] != 0, wm[["A1"]] != wm[["B1"]],
          # The claim about the noise genes is "they do not contaminate the two
          # planted modules", not "they end up grey". Those are different
          # claims, and only the first is about the construction: whether the
          # leftovers form a module of their own or fall to grey is a property
          # of dynamicTreeCut's cut height, which this file has no business
          # asserting. Measured in the container the block correlations are
          # 0.92 / 0.89 within, 0.03 between and 0.002 among the noise genes,
          # so 20% is a ceiling with a wide margin, not a fitted threshold.
          mean(wm[paste0("N", 1:nn)] %in% c(wm[["A1"]], wm[["B1"]])) < 0.2)
# hdWGCNA end to end, because "the package loads" is not the claim being made --
# the claim is that the metacell aggregation and network construction this
# project will run on the DISC1 compartments work in this image. Same designed
# structure as above, now as counts: two 40-gene blocks driven by independent
# latents, 120 noise genes, one group of 400 cells. The two blocks must land in
# different modules, and neither in grey.
#
# Note what CP10K normalisation does to this construction: dividing by the
# library size makes block A depend negatively on latent 2 and block B on latent
# 1, so after normalisation the two blocks are anti-correlated rather than
# uncorrelated. Under networkType = "signed" that pushes them apart, which is
# the direction that makes the assertion easier -- worth saying out loud, since
# it means this test is weaker evidence of separation than it looks.
set.seed(7)
nc <- 400L; ng <- 40L; ngn <- 120L
cm <- function(l, n) matrix(rpois(n * nc, rep(l, each = n) * 8), nrow = n)
cnt <- rbind(cm(runif(nc, 0.3, 3), ng), cm(runif(nc, 0.3, 3), ng),
             matrix(rpois(ngn * nc, 8), nrow = ngn))
dimnames(cnt) <- list(c(paste0("Ga", 1:ng), paste0("Gb", 1:ng),
                        paste0("Gn", 1:ngn)), paste0("cell", seq_len(nc)))
so <- CreateSeuratObject(counts = cnt)
so$grp <- "g1"
so <- NormalizeData(so, verbose = FALSE)
so <- ScaleData(so, features = rownames(so), verbose = FALSE)
so <- RunPCA(so, features = rownames(so), npcs = 10, verbose = FALSE)
# features = is what routes SetupForWGCNA to gene_select = "custom" internally;
# passing gene_select as well would reach SelectNetworkGenes twice through `...`.
so <- SetupForWGCNA(so, wgcna_name = "toy", features = rownames(so))
so <- MetacellsByGroups(so, group.by = "grp", ident.group = "grp", k = 20,
                        max_shared = 10, min_cells = 50, reduction = "pca")
so <- NormalizeMetacells(so)
so <- SetDatExpr(so, group_name = "g1", group.by = "grp", assay = "RNA")
# Into tempdir for the network step, both arguments and cwd. ConstructNetwork
# writes its TOM where tom_outdir says, but the WGCNA call underneath it also
# takes useDiskCache = TRUE with cacheDir = ".", so a block cache lands in the
# working directory -- which, in CI, is the image's WORKDIR with only the smoke
# script bind-mounted next to it. Writable today because the container runs as
# root; this stops depending on that.
owd <- setwd(tempdir())
so <- ConstructNetwork(so, soft_power = 6, minModuleSize = 10, tom_name = "toy",
                       tom_outdir = file.path(tempdir(), "TOM"),
                       overwrite_tom = TRUE)
setwd(owd)
hmod <- GetModules(so)
n_meta <- ncol(hdWGCNA::GetMetacellObject(so))
# Not the modal module alone. A plurality is nearly free: a block split 14/13/13
# across three modules has a modal label and would pass a modal-only check while
# the thing being claimed -- that the block lands together, somewhere that is not
# grey -- is false. So the modal label carries a *share* with it, and every gene
# has to be present in the table to begin with (match() returns NA for genes
# hdWGCNA dropped, and NAs excluded from a table() are invisible).
# 0.7 rather than 1.0: which of 40 co-expressed genes falls to grey at the
# margin is a property of dynamicTreeCut's cut height, so demanding unanimity
# would be asserting that. A 70% share cannot be reached by a split block, which
# is the failure the check exists for. The metacells make this easier than the
# single-cell numbers suggest -- averaging ~20 cells lifts within-block
# correlation well above the 0.65 measured on the raw cells.
share <- function(g) {
  m <- as.character(hmod$module[match(g, hmod$gene_name)])
  if (anyNA(m)) return(c(mod = NA_character_, frac = "0"))
  tb <- sort(table(m), decreasing = TRUE)
  c(mod = names(tb)[1], frac = as.character(tb[[1]] / length(g)))
}
sa <- share(paste0("Ga", 1:ng)); sb <- share(paste0("Gb", 1:ng))
mod_a <- sa[["mod"]]; mod_b <- sb[["mod"]]
stopifnot(is.data.frame(hmod), n_meta > 20,
          all(c("gene_name", "module", "color") %in% colnames(hmod)),
          !is.na(mod_a), !is.na(mod_b), mod_a != "grey", mod_b != "grey",
          mod_a != mod_b,
          as.numeric(sa[["frac"]]) >= 0.7, as.numeric(sb[["frac"]]) >= 0.7)
# dorothea's regulons ship as an .rda inside the package -- that is the whole
# reason it is in the image rather than decoupleR's CollecTRI loader, which
# fetches through OmnipathR at call time. Reading it here under --network none
# is what turns that reasoning into evidence.
denv <- new.env()
utils::data("dorothea_hs", package = "dorothea", envir = denv)
reg <- get("dorothea_hs", envir = denv)
reg <- unique(as.data.frame(reg[reg$confidence %in% c("A", "B", "C"),
                                c("tf", "target", "mor")]))
stopifnot(nrow(reg) > 1e3, length(unique(reg$tf)) > 100,
          all(reg$mor %in% c(-1, 1)))
# One TF picked by a rule rather than by name, so this cannot rot when dorothea
# renumbers: the one with the most activating targets, ties broken by sort()'s
# stable order. Two conditions -- "flat" is noise, "up" has that TF's targets
# shifted in the direction its own regulon declares. The assertion is on the
# same TF across the two conditions, NOT on it beating every other TF, because
# regulons overlap heavily and a hub sharing targets with it can legitimately
# score higher. Its own score has to move, and that is derivable; being the
# maximum is not.
#
# No RNG here: the two columns share one deterministic baseline and differ only
# by the planted shift, so "up scores higher than flat" is the planted effect
# and nothing else. A random baseline would have made the same sentence true
# only in expectation -- and an unbounded draw can always land the other way,
# which is how a smoke test acquires a failure mode nobody can reproduce.
# The baseline spans +/-2 in steps of 0.1 over the genes in alphabetical order,
# against a shift of +/-3, so the shift dominates; it is non-constant because a
# constant column has zero residual variance and a t statistic of 0/0.
pos <- table(reg$tf[reg$mor == 1])
tf <- names(sort(pos[pos >= 20], decreasing = TRUE))[1]
uni <- sort(unique(reg$target))
base <- (((seq_along(uni) * 7L) %% 41L) - 20L) / 10
mm <- cbind(flat = base, up = base)
rownames(mm) <- uni
tg <- reg[reg$tf == tf, ]
mm[tg$target[tg$mor == 1], "up"] <- mm[tg$target[tg$mor == 1], "up"] + 3
mm[tg$target[tg$mor == -1], "up"] <- mm[tg$target[tg$mor == -1], "up"] - 3
ulm <- decoupleR::run_ulm(mm, reg, .source = "tf", .target = "target",
                          .mor = "mor", minsize = 10)
utf <- ulm[ulm$source == tf, ]
stopifnot(all(c("statistic", "source", "condition", "score", "p_value") %in%
              colnames(ulm)), all(ulm$statistic == "ulm"), nrow(utf) == 2L,
          utf$score[utf$condition == "up"] > utf$score[utf$condition == "flat"],
          utf$score[utf$condition == "up"] > 0,
          utf$p_value[utf$condition == "up"] < 0.01)
# UCell and GSVA are the two scoring routes a module has to survive: UCell for
# per-cell scores in the atlas, ssGSEA for per-sample scores in the bulk
# cohorts. Same toy question for both -- a 25-gene set raised in 10 of 20
# samples -- so that a disagreement between them is visible.
#
# Deterministic for the same reason as the block above, and here it buys
# something specific: both assertions below are strict separations, and a
# Poisson draw makes a strict separation a probabilistic claim rather than a
# structural one. The baseline is a modular pattern spanning 10..50, so the +80
# shift puts the signature genes strictly above every other gene in the raised
# samples. Checked in the container rather than assumed: the 25 signature genes
# occupy ranks 1..25 in every one of the 10 raised samples, and average rank
# 149.9 of 300 in the other 10 -- i.e. the separation the tests assert is a
# property of the matrix, not of the draw.
gn <- paste0("g", 1:300); sn <- paste0("s", 1:20)
em <- outer(seq_along(gn), seq_along(sn), function(i, j) ((i * 7L + j) %% 41L) + 10L)
dimnames(em) <- list(gn, sn)
sig <- gn[1:25]; hi <- sn[1:10]; lo <- setdiff(sn, hi)
em[sig, hi] <- em[sig, hi] + 80L
uc <- as.matrix(UCell::ScoreSignatures_UCell(em, features = list(prog = sig),
                                             maxRank = 150))
gsc <- gsva(ssgseaParam(em, list(prog = sig), minSize = 5), verbose = FALSE)
stopifnot(nrow(uc) == 20L, "prog_UCell" %in% colnames(uc),
          min(uc[hi, "prog_UCell"]) > max(uc[lo, "prog_UCell"]),
          identical(dim(gsc), c(1L, 20L)),
          min(gsc["prog", hi]) > max(gsc["prog", lo]))
# slingshot on points along a quarter circle, cut into five clusters in order.
# slingshot builds an MST over the cluster centroids and reads lineages off it,
# so asserting the lineage c1 -> c5 is asserting the shape of that MST. "Points
# on a curve give a path" is *not* true in general -- it depends on the spacing
# -- so it was checked on these centroids rather than reasoned about: consecutive
# centroids are 3.13 apart and the closest non-consecutive pair is 6.17, a factor
# of two, which makes the path the unique MST. Pseudotime must then recover the
# parameter the points were generated from. Rank correlation rather than
# Pearson: slingshot's pseudotime is arc length, which is monotone in the
# parameter but not linear in it, so only the ordering is derivable here.
#
# dist.method = "simple" is what makes the paragraph above an argument rather
# than a description of one observed run. Those two numbers are Euclidean
# distances between the cluster means, and only "simple" uses that quantity:
# TrajectoryUtils::createClusterMST takes the `dist.method == "simple"` branch
# to `dist(centers)`, whereas slingshot's own default "slingshot" falls through
# to .dist_clusters_scaled, and with the full rather than the diagonal
# covariance: the selecting condition is `min(table(clusters)) > ncol(x)`, and
# by that point `clusters` is the 300x5 one-hot weight matrix slingshot built
# from the labels, so `table()` tabulates its 1200 zeros and 300 ones -- min 300
# against 2 dimensions. (Not "60 cells per cluster > 2 dimensions", which is the
# same verdict reached by arithmetic the function does not perform.)
# Under that metric the 2x margin measured above says nothing, so
# the assertion would have been pinned to whatever the run happened to produce.
# Fixing the metric rather than remeasuring under the default: the point of the
# check is that slingshot recovers a known ordering, and "simple" is the setting
# in which the ordering is known ahead of the run.
#
# Evenly spaced points and a deterministic radial wobble rather than runif/rnorm:
# with 60 points per cluster the centroids of a random sample would wander, and
# the 2x margin above is a statement about *these* centroids. Randomness here
# would have made the margin a distribution with no floor.
np <- 300L
tt <- seq(0, 1, length.out = np)
rad <- 10 + 0.15 * sin(seq_len(np))
rd <- cbind(d1 = cos(tt * pi / 2) * rad,
            d2 = sin(tt * pi / 2) * rad)
rownames(rd) <- paste0("p", seq_len(np))
sds <- slingshot(rd, clusterLabels = paste0("c", cut(tt, 5, labels = FALSE)),
                 start.clus = "c1", dist.method = "simple")
lin <- slingLineages(sds); pt <- slingPseudotime(sds)
stopifnot(length(lin) == 1L, identical(unname(lin[[1]]), paste0("c", 1:5)),
          identical(dim(pt), c(np, 1L)), !anyNA(pt),
          stats::cor(pt[, 1], tt, method = "spearman") > 0.95)
# hgu219.db is the array annotation for GSE70353 (Affymetrix HG-U219), i.e. the
# bridge from probe ids to the gene symbols the modules are written in. Checked
# as a round trip -- symbol to probe, then that probe back to symbol and entrez
# id -- so that no probe id invented here can be mistaken for a verified one.
fw <- suppressMessages(AnnotationDbi::select(
  hgu219.db::hgu219.db, keys = "GAPDH", keytype = "SYMBOL", columns = "PROBEID"))
bk <- suppressMessages(AnnotationDbi::select(
  hgu219.db::hgu219.db, keys = fw$PROBEID[1], keytype = "PROBEID",
  columns = c("SYMBOL", "ENTREZID")))
stopifnot(nrow(fw) > 0, !anyNA(fw$PROBEID),
          "GAPDH" %in% bk$SYMBOL, "2597" %in% bk$ENTREZID)
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
    "vs runner-up", round(max(au[names(au) != "SPP1"]), 4),
    "/ WGCNA", as.character(packageVersion("WGCNA")),
    "toy blocks -> modules", wm[["A1"]], "and", wm[["B1"]],
    "/ hdWGCNA", as.character(packageVersion("hdWGCNA")),
    n_meta, "metacells -> modules", mod_a, "and", mod_b,
    "(block share", sa[["frac"]], "/", sb[["frac"]], ")",
    "(enrichR.live", getOption("enrichR.live"), "with no network)",
    "/ decoupleR", as.character(packageVersion("decoupleR")),
    "on dorothea A-C:", nrow(reg), "edges,", length(unique(reg$tf)), "TFs,",
    tf, "score", round(utf$score[utf$condition == "up"], 2), "vs",
    round(utf$score[utf$condition == "flat"], 2),
    "/ UCell", as.character(packageVersion("UCell")),
    "and GSVA", as.character(packageVersion("GSVA")), "both separate the set",
    "/ slingshot", as.character(packageVersion("slingshot")),
    "1 lineage, rho", round(stats::cor(pt[, 1], tt, method = "spearman"), 3),
    "/ hgu219.db GAPDH <->", fw$PROBEID[1], "\n")
