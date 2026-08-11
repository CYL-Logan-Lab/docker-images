# Package installation for the image built by the Dockerfile next to this file.
# It ships inside the image at /opt/install-Rpkgs.R, so "how was this
# environment built" can be answered from inside the container. Read the
# Dockerfile header first: it explains the four pinning layers, of which this
# file implements the first three. Layer 4 (the two GitHub-only packages) runs
# after this one, in install-github-Rpkgs.R.

# ── Assertion for pin 1: the base image must still be that base image ────────
# FROM names a digest, so normally nothing moves. But the Dockerfile header
# *states in prose* R 4.5.2 / Seurat 5.5.1, and a stated claim should be
# executable. If someone bumps the digest and forgets the prose, this fails
# immediately.
stopifnot(
  getRversion() == "4.5.2",
  utils::packageVersion("Seurat") == "5.5.1"
)

# Loaded here, called at the end: it asserts the versions that must not move
# while packages are installed on top, and one of them (scDblFinder) is
# installed by this very script, so the check is only meaningful once this layer
# has finished. See Rlib-invariants.R for what is being defended and why.
source("/opt/Rlib-invariants.R")

# install.packages rather than BiocManager::install: all three repositories are
# attached to `repos`, so the CRAN dependencies of Bioc packages also land in
# the frozen snapshot, and provenance is stated in one place.
# (BiocManager::install(ask = FALSE, update = FALSE) would also be
# non-interactive and non-upgrading; this just avoids a second resolver.)
# The Bioc version is nailed down by this URL, not by BiocManager's default.
#
# BIOCANN is a **separate** Bioconductor repository from BIOC. Annotation
# packages (org.*.eg.db, GO.db, reactome.db) do not live in the software
# repository, so without this line install.packages() reports them as
# unavailable and the assertion block below is what turns that into a build
# failure. It is pinned to the same 3.22 release as BIOC.
#
# timeout is not cosmetic. R defaults to 60 seconds *per download*, and the
# annotation tarballs are the largest things fetched here -- reactome.db 1.95.0
# is a few hundred MB and bioconductor.org redirects it to an OSN bucket. A
# dry run of this exact package list hit precisely that: "URL
# .../reactome.db_1.95.0.tar.gz: Timeout of 60 seconds was reached", then
# "download of package reactome.db failed". Because install.packages() only
# warns, the build would have carried on and failed later at the version
# assertion, reporting a missing package instead of a slow network. Raising the
# timeout does not paper over a real failure: an unreachable repository still
# fails, just not on file size.
# BIOCEXP is a **fourth** repository, added for the gene-program layer. Like
# BIOCANN it is a separate Bioconductor repository, and it exists here for
# exactly one package: dorothea, whose TF regulons ship as an .rda inside the
# package (dorothea_hs.rda). That is the whole reason it was chosen over the
# obvious alternative -- decoupleR's own CollecTRI loader fetches the regulons
# through OmnipathR at call time, i.e. over the network, on the day the analysis
# runs. Same defect that disqualified liana and SingleCellSignalR; same answer.
# It is pinned to the same 3.22 release as BIOC and BIOCANN.
options(repos = c(BIOC = "https://bioconductor.org/packages/3.22/bioc",
                  BIOCANN = "https://bioconductor.org/packages/3.22/data/annotation",
                  BIOCEXP = "https://bioconductor.org/packages/3.22/data/experiment",
                  CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/2026-08-06"),
        Ncpus = 4, timeout = 1200)

# Listing them in dependency order is for humans; the real order comes from
# install.packages resolving dependencies itself.
PKG_PINNED <- c(
  xgboost       = "3.2.1.1",   # CRAN snapshot
  BiocNeighbors = "2.4.0",
  BiocSingular  = "1.26.1",
  ScaledMatrix  = "1.18.0",
  metapod       = "1.18.0",
  edgeR         = "4.8.2",
  scuttle       = "1.20.0",
  bluster       = "1.20.0",
  scran         = "1.38.1",
  scater        = "1.38.1",
  scDblFinder   = "1.24.10",

  # ── Pathway enrichment (added for the ASPC state characterisation step) ────
  # The gene sets ship *inside* org.Hs.eg.db / GO.db / reactome.db, which is the
  # whole point of choosing them: an enrichment run needs no network at analysis
  # time, and the gene-set version is fixed by the image digest like everything
  # else. msigdbr was considered and rejected -- since 26.x it fetches gene sets
  # over the network at call time, which would make the result depend on the day
  # the analysis ran rather than on the image.
  #
  # DOSE / GOSemSim / AnnotationDbi / graphite are pinned even though nothing
  # here calls them by name: clusterProfiler, enrichplot and ReactomePA are thin
  # over them (the enrichment result class itself is DOSE's, the term-similarity
  # step used when collapsing redundant GO terms is GOSemSim's, every annotation
  # query goes through AnnotationDbi, and ReactomePA's pathway topology comes
  # from graphite). An unpinned one of these drifting is exactly the kind of
  # silent change that alters enrichment output, so they get the same treatment
  # as everything else. The base image also predates them, so leaving them
  # unnamed risks keeping whatever version happened to come along for the ride.
  AnnotationDbi   = "1.72.0",
  GO.db           = "3.22.0",
  org.Hs.eg.db    = "3.22.0",
  reactome.db     = "1.95.0",
  GOSemSim        = "2.36.0",
  DOSE            = "4.4.0",
  graphite        = "1.56.0",
  clusterProfiler = "4.18.4",
  ReactomePA      = "1.54.0",
  enrichplot      = "1.30.5",
  fgsea           = "1.36.2",

  # ── Cell-cell communication (added for the ASPC-myeloid state step) ────────
  # SingleCellSignalR 2.0.1 was intended here as a *second, independent*
  # ligand-receptor implementation alongside CellChat, and is deliberately
  # absent. Since 2.x it is a thin wrapper over BulkSignalR, and BulkSignalR
  # does not ship the LRdb: its .onLoad() downloads LRdb, Reactome, GO-BP and
  # Network from https://partage-dev.montp.inserm.fr:9192/CBSB/ into a
  # BiocFileCache (and its cache helper sets ssl_verifypeer = 0L,
  # ssl_verifyhost = 0L, i.e. with TLS verification switched off). Attaching the
  # package therefore needs the network, and the database version would depend
  # on the day the analysis ran -- the same defect that disqualified liana, and
  # the opposite of what every other database in this image does.
  #
  # It also fails to build here for a shallower reason -- BulkSignalR pulls in
  # SpatialExperiment -> magick, which needs libmagick++-dev, absent from the
  # base image. That one is fixable with an apt line. It was not fixed, because
  # fixing the build would not fix the provenance.
  #
  # Consequence, stated rather than hidden: CellChat is the only ligand-receptor
  # *scoring* implementation in this image. What remains is a cross-check at the
  # resource level -- NicheNet's lr_network prior (baked in below) assembles its
  # 4986 pairs from a different starting point than CellChatDB does, so a
  # reported pair can be asked whether both resources contain it.
  # Do not oversell that check: 4496 of those 4986 pairs carry database ==
  # "omnipath", i.e. the prior is mostly one aggregator, whereas CellChatDB is
  # curated by its authors from KEGG plus literature. Different inclusion
  # criteria, not independent evidence -- agreement is weak support and
  # disagreement is worth looking at, which is all it is used for.
  #
  # ComplexHeatmap and circlize are dependencies of CellChat and nichenetr, but
  # they are pinned by name rather than left to dependency resolution because
  # they draw the figures -- a silent bump changes plots that end up in a
  # manuscript.
  #
  # The rest of this block is the dependency closure of CellChat and nichenetr
  # that the base image does not already carry. They are listed explicitly for
  # one specific reason: the GitHub layer installs a package from a local
  # directory with repos = NULL, which does not resolve dependencies at all, so
  # anything missing there is a build failure with a package name rather than
  # something quietly pulled from an unpinned source. Naming them here also
  # means their versions are asserted rather than merely recorded.
  #
  # Note which packages are deliberately NOT named: everything the base image
  # already ships (irlba, igraph, Rcpp, plotly, future, dplyr, ...). Naming an
  # already-installed package would make install.packages() replace it with the
  # snapshot's version -- the snapshot carries Matrix 1.7-6 against the image's
  # 1.7-5, and irlba/igraph sit under every PCA and clustering result the
  # downstream project has already produced. Missing dependencies are installed;
  # satisfied ones are left alone. Rlib-invariants.R asserts that this held.
  ComplexHeatmap = "2.26.1",

  circlize     = "0.4.18",
  colorspace   = "2.1-3",
  collapse     = "2.1.7",
  ggnetwork    = "0.5.14",
  ggpubr       = "1.0.0",
  ggalluvial   = "0.12.6",
  sna          = "2.8",
  svglite      = "2.2.2",
  NMF          = "0.28",
  shape        = "1.4.6.1",
  shadowtext   = "0.1.6",
  DiagrammeR   = "1.0.12",
  mlrMBO       = "1.1.6",
  emoa         = "0.5-3",
  DiceKriging  = "1.6.1",
  parallelMap  = "1.5.1",
  caret        = "7.0-1",
  randomForest = "4.7-1.2",
  Hmisc        = "5.2-6",
  fdrtool      = "1.2.18",

  # ── Gene programs, TF activity, trajectory, bulk projection (image v5) ──────
  # The downstream project stopped asking "how many cells of type X" and started
  # asking "how much of program P", because the cluster proportions turned out
  # not to be stable across donors. That question needs a co-expression module
  # layer (hdWGCNA over WGCNA), a way to score those modules in cells and in
  # bulk samples (UCell, GSVA), a TF-activity readout (decoupleR over dorothea's
  # regulons), a trajectory (slingshot), and the bulk-side machinery to relate
  # the scores to metabolic traits (sva, glmnet, and the array annotation for
  # the METSIM cohort). hdWGCNA itself is GitHub-only and lives in layer 4;
  # everything it needs that the image does not already carry is named here, for
  # the reason given in the CellChat block above -- the GitHub layer installs
  # with repos = NULL and resolves nothing, so a missing dependency there is a
  # build failure with a package name rather than a silent unpinned fetch.
  #
  # WGCNA's three heavy dependencies (impute, preprocessCore from Bioc,
  # fastcluster and dynamicTreeCut from CRAN) are named rather than left to
  # resolution because the module assignment is a *result*: dynamicTreeCut is
  # the tree-cut algorithm that decides which genes end up in which module, and
  # a silent bump there changes the modules a manuscript figure is drawn from.
  #
  # enrichR is here only because hdWGCNA Depends on it. Read that as a warning
  # rather than an endorsement: its .onAttach calls listEnrichrSites(), which
  # issues six untimed httr::GET requests to maayanlab.cloud, so *attaching*
  # hdWGCNA reaches for the network. Two consequences, handled in two places.
  # At build time the network is real, so this file never attaches anything --
  # see the loadNamespace() loadability check at the bottom. At smoke-test time
  # there is no network, has_internet() is false, and attaching degrades to
  # "No internet connection could be found" with enrichR.live = FALSE.
  # Nothing downstream may route enrichment through it -- the offline path
  # (clusterProfiler + the sha256-pinned Hallmark GMT) is already in this image
  # and is the one to use.
  #
  # msigdbr is deliberately still absent, for the reason given in the enrichment
  # block above: since 26.x it fetches gene sets over the network at call time.
  # SCENIC is likewise absent -- RcisTarget needs multi-gigabyte motif-ranking
  # databases downloaded from resources.aertslab.org at analysis time, which is
  # the same provenance defect one more time. decoupleR + dorothea is the
  # offline TF-activity path, and it was the alternative the analysis plan
  # already named. What that costs, stated plainly: no motif-based regulon
  # discovery, only scoring against a fixed curated regulon set.
  # monocle3 is absent too: GitHub-only with a large dependency closure, and
  # slingshot answers the question that was actually asked (an ordering along
  # the progenitor-to-remodelling axis), so a second implementation would be
  # cost without a decision hanging on it.
  WGCNA          = "1.74",
  dynamicTreeCut = "1.63-1",
  fastcluster    = "1.3.0",
  impute         = "1.84.0",
  preprocessCore = "1.72.0",
  GeneOverlap    = "1.46.0",
  enrichR        = "3.4",
  tester         = "0.3.0",
  proxy          = "0.4-29",
  ggraph         = "2.2.2",
  tidygraph      = "1.3.1",
  ggrepel        = "0.9.8",

  # Module scoring. UCell is rank-based and so is not rescaled by the rest of
  # the matrix, which is what makes a score comparable between the two datasets;
  # GSVA is the bulk-side counterpart. Both are named because the scores they
  # produce are the numbers the metabolic association is computed on.
  UCell          = "2.14.0",
  GSVA           = "2.4.9",
  GSEABase       = "1.72.0",

  # TF activity. bcellViper is not optional decoration -- dorothea Imports it.
  # (OmnipathR is only in dorothea's Suggests, so it is not pulled in, which is
  # the property that keeps this path offline.)
  decoupleR      = "2.16.0",
  dorothea       = "1.22.0",
  bcellViper     = "1.46.0",

  # Trajectory.
  slingshot       = "2.18.0",
  TrajectoryUtils = "1.18.0",
  princurve       = "2.1.6",

  # Bulk projection. hgu219.db is the probe-to-gene map for GPL13667, the array
  # behind the METSIM bulk cohort that carries the metabolic phenotypes; it is
  # an annotation package for the same reason the enrichment databases are --
  # the mapping ships inside the image instead of being fetched from GEO on the
  # day the analysis runs.
  sva            = "3.58.0",
  glmnet         = "5.0",
  hgu219.db      = "3.2.3"
)

install.packages(names(PKG_PINNED))

# ── Assertion: what got installed must be what this file says ────────────────
# This block is not optional. install.packages() only *warns* when a package
# fails to install and still exits 0, so without an assertion the build would
# succeed, the image would ship, and the missing package would surface months
# later in the middle of an analysis. The check covers both "did it install"
# and "is it the stated version".
#
# Comparison goes through numeric_version rather than string equality: R
# normalises the separator when printing, so a package whose DESCRIPTION says
# "2.1-3" reads back as "2.1.3" and a string compare would report a mismatch
# that does not exist. Versions above are written the way the repository index
# spells them, so that they can be checked against it by eye.
got <- vapply(names(PKG_PINNED), function(p)
  tryCatch(as.character(utils::packageVersion(p)),
           error = function(e) NA_character_), character(1))
# Two steps rather than `is.na(got) | ...`: numeric_version() errors on NA
# instead of propagating it, which would abort here with a parse error instead
# of reaching the message below that names the missing package.
present <- !is.na(got)
bad <- !present
bad[present] <- numeric_version(got[present]) != numeric_version(PKG_PINNED[present])
if (any(bad)) {
  stop("package versions disagree with the Dockerfile:\n",
       paste(sprintf("  %-14s expected %-10s got %s",
                     names(PKG_PINNED)[bad], PKG_PINNED[bad],
                     ifelse(is.na(got[bad]), "<not installed>", got[bad])),
             collapse = "\n"),
       "\nUpstream moved. Write the new versions into PKG_PINNED and rebuild;",
       "\ndo not delete this assertion.")
}

# Installable does not mean loadable: with a missing C-level dependency the
# package installs fine and loading is what blows up.
# Note this only runs when this layer is actually built; a cache hit skips it.
# The per-CI-run verification lives in the workflow -- see the header.
#
# loadNamespace() rather than library(), and the difference is not cosmetic.
# Loading a namespace is what runs dyn.load() and .onLoad() -- which is the
# whole of what this check is for. Attaching additionally runs .onAttach(), and
# one package here has an .onAttach() worth refusing to run: enrichR 3.4 calls
# listEnrichrSites(), which issues **six httr::GET requests to maayanlab.cloud
# with no timeout configured**. This build layer has network, so unlike the
# smoke test it would really contact that host -- an unpinned third-party
# service outside the four repositories this file pins, on every uncached
# build. Its errors are caught (the tryCatch error handler just messages), so
# the exposure is not a spurious failure; it is a build that hangs when the
# endpoint black-holes, which no timeout will interrupt.
# Attaching is exercised where it is safe instead: the smoke test attaches
# hdWGCNA under --network none, where has_internet() is false and the request
# is never made.
invisible(lapply(names(PKG_PINNED), loadNamespace))

# Loadable does not mean usable either -- the annotation packages are SQLite
# databases behind an R facade, and a truncated download gives you a package
# that attaches cleanly and then fails on the first query. So query all three
# here, with a gene that is not going anywhere. GAPDH is entrez 2597.
#
# The three checks are chained rather than independent, and deliberately so: the
# GO ids come out of org.Hs.eg.db and are then resolved in GO.db, so the pair has
# to agree with each other. That is a much better integrity test than a row count
# would be, and it needs no magic constant -- a "keys(GO.db) > N" style check
# encodes a guess about how big the ontology is this release, and fails the build
# when the guess is wrong rather than when the database is broken.
gapdh <- AnnotationDbi::select(org.Hs.eg.db::org.Hs.eg.db, keys = "GAPDH",
                               keytype = "SYMBOL", columns = c("ENTREZID", "GO"))
stopifnot(nrow(gapdh) > 0, unique(gapdh$ENTREZID) == "2597")

go_ids <- unique(gapdh$GO[!is.na(gapdh$GO)])
# Intersect before select(): the two databases ship separately and org.Hs.eg.db
# occasionally still references a GO id that GO.db has retired, which would make
# select() error out on an otherwise healthy pair. So the claim being asserted is
# "nearly all of them resolve", which is the real consistency requirement, rather
# than "every single one does".
go_have <- intersect(go_ids, AnnotationDbi::keys(GO.db::GO.db))
stopifnot(length(go_ids) > 0, length(go_have) >= 0.9 * length(go_ids))
go_tm <- AnnotationDbi::select(GO.db::GO.db, keys = go_have,
                               keytype = "GOID", columns = "TERM")
stopifnot(nrow(go_tm) == length(go_have), !anyNA(go_tm$TERM), all(nzchar(go_tm$TERM)))

# GAPDH is in glycolysis, so Reactome has to know about it. PATHNAME is prefixed
# with the species, which is also the check that the human pathways are present
# and not only some other organism's.
rx <- AnnotationDbi::select(reactome.db::reactome.db, keys = "2597",
                            keytype = "ENTREZID", columns = "PATHNAME")
stopifnot(nrow(rx) > 0, any(grepl("^Homo sapiens", rx$PATHNAME)))

cat("annotation databases queryable: GAPDH ->", length(go_ids), "GO ids,",
    nrow(go_tm), "resolved in GO.db;", sum(grepl("^Homo sapiens", rx$PATHNAME)),
    "human Reactome pathways\n")

# ── The two databases added in v5, checked the same way ─────────────────────
# Same argument as above: these are data shipped inside packages, and a package
# whose data object failed to unpack still attaches cleanly. The point of
# choosing dorothea and hgu219.db over their networked alternatives was that
# the data is *in the image*, so that claim gets an assertion rather than a
# sentence.
#
# dorothea_hs is lazy-loaded data, not an exported object, so it has to be
# pulled out with data(..., envir=) rather than dorothea::dorothea_hs.
de <- new.env()
utils::data("dorothea_hs", package = "dorothea", envir = de)
reg <- get("dorothea_hs", envir = de)
stopifnot(is.data.frame(reg), nrow(reg) > 1e4,
          all(c("tf", "confidence", "target", "mor") %in% colnames(reg)),
          all(c("NFKB1", "RELA", "SMAD3", "TEAD1") %in% reg$tf),
          all(reg$confidence %in% c("A", "B", "C", "D", "E")),
          all(reg$mor %in% c(-1, 1)))
# A/B/C are the confidence levels the downstream step will actually keep, so
# assert that restricting to them leaves a usable regulon rather than an empty
# one -- "the file is present" and "the subset you will use is non-empty" are
# different claims.
abc <- reg[reg$confidence %in% c("A", "B", "C"), ]
stopifnot(nrow(abc) > 1e3, length(unique(abc$tf)) > 100)

# hgu219.db is the probe-to-gene map for GPL13667, the array behind the METSIM
# bulk cohort. The check is a **round trip** rather than a lookup of a probe id
# written into this file: symbol -> probe, then that probe -> symbol, and the
# two have to agree. No magic constant is involved, so the assertion cannot
# fail because a platform annotation renumbered its probes -- it fails when the
# database is genuinely inconsistent or truncated, which is the only thing it
# is meant to catch. Same shape as the org.Hs.eg.db -> GO.db chain above.
fwd <- AnnotationDbi::select(hgu219.db::hgu219.db, keys = "GAPDH",
                             keytype = "SYMBOL", columns = "PROBEID")
stopifnot(nrow(fwd) > 0, !anyNA(fwd$PROBEID))
back <- AnnotationDbi::select(hgu219.db::hgu219.db, keys = fwd$PROBEID[1],
                              keytype = "PROBEID", columns = c("SYMBOL", "ENTREZID"))
stopifnot(nrow(back) > 0, "GAPDH" %in% back$SYMBOL, "2597" %in% back$ENTREZID)
n_probe <- length(AnnotationDbi::keys(hgu219.db::hgu219.db, keytype = "PROBEID"))
stopifnot(n_probe > 1e4)

cat("v5 databases queryable: dorothea", nrow(reg), "TF-target edges (",
    length(unique(reg$tf)), "TFs;", nrow(abc), "at confidence A-C) /",
    "hgu219.db", n_probe, "probes, GAPDH <->", fwd$PROBEID[1], "\n")

# ── Nothing above was allowed to move the numerical chain ────────────────────
# Everything installed here brought its own dependency closure with it, and
# install.packages() upgrades an already-installed package without asking
# whenever some new dependency declares a higher minimum. This is where that
# gets caught. See Rlib-invariants.R.
assert_invariants("after the CRAN/Bioc layer")

# The manifest is written by install-github-Rpkgs.R, not here: that layer runs
# last, and a manifest written at this point would not list the packages it
# installs.
