# ============================================================================
# R environment for t2d-sc-lipid (snRNA-seq annotation pipeline, Seurat v5).
# Downstream project: https://github.com/CYL-Logan-Lab/t2d-sc-lipid
#
# ── The unit of reproducibility is the image, not "rebuild and get the same" ─
# Downstream pins the image by digest, and a digest is content-addressed, so
# "which environment produced this analysis" always has an exact answer. This
# recipe's job is to make the image buildable and to make the built image match
# its own claims (version mismatch fails the build). It does NOT promise that
# rebuilding six months from now yields a byte-identical image -- see pin 3.
#
# ── Four pinning layers ─────────────────────────────────────────────────────
#   1. Base image taken by **OCI manifest digest**, not by the :5.5.1 tag. A tag
#      is a mutable reference: the maintainer re-pushes it and you silently get
#      a different image. A digest cannot change. R 4.5.2 / Seurat 5.5.1 come
#      from this layer, and the install script **asserts** both versions up
#      front, so swapping the base image fails the build instead of quietly
#      producing a different environment.
#   2. CRAN goes through Posit's **date-frozen** snapshot (Ubuntu noble
#      binaries). With a rolling mirror such as cloud.r-project.org, the same
#      Dockerfile would install different code today and six months from now.
#   3. Bioconductor has no dated snapshot service, only per-release-branch
#      repositories -- the Bioc version is nailed down by the URL below, but the
#      release branch itself keeps rolling out patch versions. So every direct
#      dependency gets an **explicit version assertion**; a mismatch fails the
#      build. Be clear about the limit of this layer: the assertions cover only
#      the packages named here. Transitive dependencies pulled in by Bioc are
#      NOT pinned; their patch versions can drift without failing the build, and
#      the drift shows up only in /opt/Renv-manifest.tsv inside the image. So
#      "the same recipe rebuilds to the same environment" is false for this
#      file; what is true is "downstream, pinned by digest, always gets the same
#      environment".
#      A failed assertion means upstream moved: write the new version into
#      PKG_PINNED and rebuild -- do **not** delete the assertion.
#   4. **GitHub packages by commit SHA**, not by tag or branch. Three packages
#      here exist on neither CRAN nor Bioconductor (checked against the Bioc
#      3.22 PACKAGES index): CellChat, nichenetr, and hdWGCNA. They have to be
#      installed from source repositories -- which have no snapshot service at
#      all and whose tags can be moved. A commit SHA is the only immutable
#      reference GitHub offers. See install-github-Rpkgs.R.
#
# ── Why add anything on top of satijalab/seurat ─────────────────────────────
# Four reasons, and the base image supplies none of them.
#   1. Nucleus-level doublet scoring with scDblFinder, plus its dependencies
#      (scran, scuttle, scater, bluster, edgeR, BiocNeighbors, BiocSingular,
#      metapod, ScaledMatrix) and xgboost from CRAN.
#   2. Pathway enrichment on cell-state marker sets: clusterProfiler,
#      ReactomePA, enrichplot, fgsea and the annotation databases they read
#      (org.Hs.eg.db, GO.db, reactome.db). The annotation packages carry the
#      gene sets inside them, so enrichment runs offline and the gene-set
#      version is fixed by this image's digest -- same guarantee as the code.
#      Note this pulls in a *third* repository, the Bioconductor annotation
#      repo; see the options(repos = ...) call in install-Rpkgs.R.
#   3. Ligand-receptor / cell-cell communication between ASPC and myeloid cell
#      states: CellChat and nichenetr, plus what they draw with (ComplexHeatmap,
#      circlize, NMF, ggalluvial).
#      Same offline requirement as the gene sets, for the same reason: an
#      interaction database fetched at analysis time makes the result depend on
#      the day the analysis ran. That requirement decided which packages are
#      here -- liana and SingleCellSignalR were both dropped for failing it, for
#      reasons recorded where each would have been installed. CellChatDB ships
#      inside its package; NicheNet's prior networks do not, so they are
#      downloaded here and checksummed -- see the layer below.
#   4. **Gene programs rather than cell proportions** (added in v5). The project
#      found cluster proportions to be unstable across donors and moved the
#      question from "how many cells of type X" to "how much of program P",
#      which needs a co-expression layer (WGCNA + hdWGCNA and their closure),
#      two scoring routes so a module can be carried from nuclei to bulk arrays
#      (UCell per cell, GSVA/ssGSEA per sample), a TF-activity layer (decoupleR
#      with dorothea's regulons), a trajectory layer (slingshot -- and *not*
#      RNA velocity, which the data cannot support: no BAMs, no unspliced
#      counts), and the bulk side of the bridge (sva, glmnet, and hgu219.db for
#      the HG-U219 array the METSIM bulk cohort was run on).
#      The offline rule decided membership here too, exactly as it did in 3:
#      dorothea is installed because its regulons ship as an .rda inside the
#      package, whereas decoupleR's own CollecTRI loader would fetch them
#      through OmnipathR at call time. That pulls in a *fourth* repository, the
#      Bioconductor experiment-data repo. SCENIC/RcisTarget (multi-GB motif
#      rankings fetched at analysis time), msigdbr (network at call time; the
#      Hallmark GMT is already sha256-pinned in the downstream repo) and
#      monocle3 were all excluded for the same reason or for closure size --
#      recorded where each would have been installed.
#
# ── The NicheNet priors are downloaded before the R layers, deliberately ────
# 420 MB from Zenodo. Putting it first means editing an installer does not
# re-download it: the build cache invalidates a layer and everything after it,
# never anything before. The URLs and their md5 sums are pinned in
# nichenet-priors.md5 -- Zenodo records are immutable once published, so the
# checksum is a real integrity check rather than a guess about what is there.
#
# ── The smoke test lives outside this file ──────────────────────────────────
# The install layers below do run library() once, but only when that layer is
# actually built: a cache hit skips the whole layer, and putting the test in its
# own RUN does not change that (cache matching walks parent layers in order).
# For "every CI run really verifies it", the test has to run outside the
# Dockerfile -- see the smoke-test step in .github/workflows/build.yml, which
# docker-runs the image this build actually produced.
# ============================================================================
FROM satijalab/seurat@sha256:048d965487afc2961c450879692281a73e24f6de47360ed2f11b31112ebd844e

LABEL org.opencontainers.image.source="https://github.com/CYL-Logan-Lab/docker-images"
LABEL org.opencontainers.image.description="R env for CYL-Logan-Lab/t2d-sc-lipid: Seurat 5.5.1 + scDblFinder + clusterProfiler/ReactomePA + CellChat/nichenetr + hdWGCNA/decoupleR/slingshot/UCell/GSVA, all with offline databases"
LABEL org.opencontainers.image.base.name="satijalab/seurat@sha256:048d965487afc2961c450879692281a73e24f6de47360ed2f11b31112ebd844e"

ENV LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# Analysis code reads the priors from here rather than hard-coding /opt/nichenet,
# so the path is stated once and is visible from inside a running container.
ENV NICHENET_PRIOR_DIR=/opt/nichenet

# Zenodo record 7074291, "NicheNet-v2: final networks and ligand-target
# matrices". Only the six human files; the mouse set is another 300 MB that
# nothing here will ever read.
#
# --fail matters: without it curl writes an HTTP error page to the output file
# and exits 0, and the failure would surface as a corrupt .rds months later.
# md5sum -c is the second line of defence and the one that catches a truncated
# transfer, which --fail does not.
#
# The base image has no curl -- the first CI build of this layer failed with
# "/bin/sh: 1: curl: not found", which no amount of local reasoning had caught,
# so it is installed here as build-time transport. This is the only apt layer in
# the file and it is deliberately not version-pinned: pinning a package
# version in a rolling Ubuntu archive breaks the build the day that version is
# superseded, and durable package-level reproducibility would need an Ubuntu
# snapshot repository, not a version string. What the pinning discipline
# actually promises is on the other side of this: deployed images are consumed
# by digest, and the bytes fetched here are md5-checked after the download loop.
#
# Only curl, not ca-certificates: the base image already ships the trust store
# (ca-certificates 20240203, a 146-certificate bundle that verifies Zenodo's
# current chain), and naming it here would upgrade that system-wide bundle,
# which R reads too. Not naming it leaves it alone -- checked, not assumed.
# Installing curl does still upgrade libcurl4t64 and libcurl4-openssl-dev
# (8.5.0-2ubuntu10.9 -> .11 as of this writing), and several already-built R
# packages link libcurl at runtime -- curl, arrow, Rsamtools, rhdf5. That is a
# patch move inside one ABI, not a version change any of them would notice, but
# it is a smaller blast radius rather than none, which is worth stating plainly
# instead of claiming the layer touches nothing but one executable.
#
# --retry covers the third-party half of this: Zenodo is not our infrastructure
# and the largest file here is 262 MB, so a transient 5xx should cost a retry
# rather than a build.
#
# libmagick++-dev is the second package here, and it is present for a reason
# worth writing down because nothing in the analysis wants ImageMagick. The
# chain is: GSVA 2.4.9 Imports SpatialExperiment 1.20.0, which Imports magick,
# whose configure step needs Magick++.h. All three are hard Imports, not
# Suggests, so there is no dependency flag that avoids it -- the v5 build failed
# at exactly this point ("fatal error: Magick++.h: No such file or directory",
# run 31491127807). GSVA is wanted for the bulk half of the program layer:
# scoring a gene program across the METSIM cohorts is ssGSEA's job, and it is
# the method a reader will expect there. SpatialExperiment only reaches for
# magick when it reads spatial images, which this project never does; the
# dependency is structural, not functional.
#
# The alternative was dropping GSVA and scoring programs with UCell (already in
# this image, rank-based, works on bulk). Rejected: that trades the field's
# standard method for an unconventional one to avoid installing a leaf library.
# Keeping both means the two scorings can be compared, which is worth more.
#
# Blast radius, stated the same way as curl's above: unlike curl -- which
# upgrades libcurl4t64, a library four already-built R packages link at runtime
# -- ImageMagick is not linked by anything else in this image. The only consumer
# is the magick package built in the next layer. The cost is size, not risk, and
# it is not small: the -dev package pulls the ImageMagick 6 runtime plus headers.
# The measured delta is recorded in the v5 entry of the project's decision log
# rather than guessed at here.
COPY nichenet-priors.md5 /opt/nichenet/nichenet-priors.md5
RUN set -eu; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl libmagick++-dev; \
    rm -rf /var/lib/apt/lists/*; \
    cd /opt/nichenet; \
    while read -r _ f; do \
      curl -sSfL --retry 5 --retry-delay 5 --retry-connrefused \
           -o "$f" "https://zenodo.org/records/7074291/files/${f}?download=1"; \
    done < nichenet-priors.md5; \
    md5sum -c nichenet-priors.md5; \
    chmod 0444 /opt/nichenet/*

# The installers are their own files rather than heredocs: as plain .R they get
# R syntax highlighting, linting and `Rscript -e 'parse(...)'` for free, none of
# which work on text embedded in a Dockerfile. Build-cache behaviour is the same
# either way -- the layer key is the file's content, so editing a script
# invalidates its install layer and nothing else does.
#
# CRAN/Bioc and GitHub are two layers rather than one because they fail for
# different reasons and iterate at different speeds: the GitHub packages are
# built from source against whatever this base image ships, which is the part
# that actually breaks, and keeping it last means a failed retry does not
# reinstall the ~60 packages that already succeeded.
#
# Rlib-invariants.R is sourced by both: it names the packages whose versions must
# not move, and both installers assert them after running. Most of them come from
# the base image; scDblFinder is installed by install-Rpkgs.R and then held still
# for the same reason, because its doublet scores are written into result tables.
COPY Rlib-invariants.R /opt/Rlib-invariants.R

COPY install-Rpkgs.R /opt/install-Rpkgs.R
RUN Rscript --vanilla /opt/install-Rpkgs.R

COPY install-github-Rpkgs.R /opt/install-github-Rpkgs.R
RUN Rscript --vanilla /opt/install-github-Rpkgs.R \
 && chmod 0444 /opt/Renv-manifest.tsv /opt/Rlib-invariants.R \
               /opt/install-Rpkgs.R /opt/install-github-Rpkgs.R
