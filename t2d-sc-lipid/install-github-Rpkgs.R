# Pinning layer 4: the cell-cell communication packages that exist on neither
# CRAN nor Bioconductor. Ships inside the image at /opt/install-github-Rpkgs.R.
# Read the Dockerfile header first; this file implements the fourth layer and
# runs after install-Rpkgs.R.
#
# ── Why a whole extra layer for two packages ────────────────────────────────
# CellChat and nichenetr are distributed only from their authors' GitHub
# repositories (checked against the Bioc 3.22 and the frozen CRAN indexes:
# neither is present in either). GitHub has no snapshot service, so layers 2
# and 3 cannot cover them. What GitHub does offer is a commit SHA, which is
# content-addressed and cannot be moved -- unlike a tag or a branch, both of
# which the maintainer can repoint at different code without any visible
# change here. So every package below is fetched by SHA and its DESCRIPTION is
# checked to say the version this file claims, *before* it is installed.
#
# ── Why not remotes::install_github ─────────────────────────────────────────
# Two reasons, and the second one is the load-bearing one.
#   1. install_github resolves the ref through the GitHub API, which is rate
#      limited per IP for unauthenticated callers. CI runners share IPs, so
#      that turns an unrelated neighbour's traffic into a build failure. The
#      archive endpoint used below needs no API call and no token.
#   2. remotes honours the `Remotes:` field in a package's DESCRIPTION, which
#      installs *further* packages straight from GitHub HEAD -- unpinned, by
#      construction. That is precisely what this layer exists to prevent. Base
#      R's install.packages(repos = NULL) ignores the field entirely, so the
#      dependencies are resolved below from the pinned repositories only, and
#      a dependency that is not available there fails the build instead of
#      being silently fetched from somewhere unpinned.
#
# ── liana was considered and is deliberately absent ─────────────────────────
# It was in the original plan for this image as a third, independent
# ligand-receptor implementation. Three findings, all from its DESCRIPTION at
# commit 6cab46c54234f861ea176c3de77c4b8aa45ecb3d (0.1.14, the last commit,
# 2024-08-07 -- upstream development moved to the Python package LIANA+):
#   * It Imports basilisk and basilisk.utils, which provision a Miniconda
#     environment. That is a fourth provenance channel -- not CRAN, not
#     Bioconductor, not a checksummed archive -- and it fetches at first use,
#     i.e. inside the offline analysis container. Baking it would add roughly a
#     gigabyte to hold something this image cannot pin.
#   * Its `Remotes:` field points at five GitHub HEADs, one of them
#     sqjin/CellChat, which is the *older* CellChat repository and would
#     conflict with the pinned jinworks/CellChat below.
#   * It Imports OmnipathR, whose purpose is to fetch interaction resources
#     over the network at analysis time -- the thing this image is built to
#     avoid (see the Dockerfile header on gene-set provenance).
# Note what is and is not being claimed: this is not "liana failed to build".
# It was dropped because installing it would break the pinning discipline the
# rest of the image is built on, and loosening a pin to accommodate it was
# explicitly ruled out.
#
# The intended fallback, SingleCellSignalR from Bioconductor, was then dropped
# for the same reason (see install-Rpkgs.R: its LR database is downloaded at
# package load time). So CellChat below is the only ligand-receptor scoring
# implementation in this image, and that is a real reduction in method coverage
# rather than a wash -- it should be stated in the downstream methods section,
# not papered over. What limits the downstream claim is anyway not the method:
# it reports in how many donor x depot units a channel is reproducible, and the
# thinnest state pair has six testable units.

source("/opt/Rlib-invariants.R")
assert_invariants("before the GitHub layer")

# timeout: same reason as install-Rpkgs.R (R defaults to 60 s per download and
# the largest tarballs exceed it on a slow link). This layer downloads the two
# GitHub archives and whatever dependencies of theirs are not already present.
options(repos = c(BIOC = "https://bioconductor.org/packages/3.22/bioc",
                  BIOCANN = "https://bioconductor.org/packages/3.22/data/annotation",
                  CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/2026-08-06"),
        Ncpus = 4, timeout = 1200)

# SHAs read from the repositories on 2026-08-11; the Version column is what the
# DESCRIPTION at that SHA says, and is asserted below rather than trusted.
GH_PINNED <- list(
  list(pkg = "CellChat",  repo = "jinworks/CellChat",
       sha = "75253cd0c9e68410e6e721a6d3a0419a1d7e358f", version = "2.2.0.9001"),
  list(pkg = "nichenetr", repo = "saeyslab/nichenetr",
       sha = "66f90d5eeafef280b2b2f339b3fd70ffec1781dd", version = "2.2.1.1")
)

install_pinned_github <- function(spec) {
  cat("\n---", spec$pkg, spec$repo, substr(spec$sha, 1, 12), "---\n")

  # The archive endpoint is content-addressed by the SHA in the path, so no
  # separate checksum is pinned here: GitHub regenerates these tarballs on
  # demand and their bytes are not stable across time even for a fixed commit,
  # while the *contents* are exactly that commit. The integrity claim comes
  # from the SHA, and the version assertion below is what turns "this is some
  # commit" into "this is the commit that carries the version we claim".
  url <- sprintf("https://github.com/%s/archive/%s.tar.gz", spec$repo, spec$sha)
  tarball <- file.path(tempdir(), paste0(spec$pkg, ".tar.gz"))
  if (utils::download.file(url, tarball, mode = "wb", quiet = TRUE) != 0 ||
      !file.exists(tarball) || file.size(tarball) < 1024)
    stop("download failed or is implausibly small: ", url, call. = FALSE)

  exdir <- file.path(tempdir(), paste0(spec$pkg, "-src"))
  utils::untar(tarball, exdir = exdir)
  roots <- list.dirs(exdir, recursive = FALSE)
  if (length(roots) != 1)
    stop("expected one top-level directory in the archive, got ",
         length(roots), call. = FALSE)
  root <- roots[[1]]

  # ── The pin assertion, before anything is installed ───────────────────────
  # A SHA guarantees "the same code every time"; it does not guarantee that the
  # code is what this file's table says it is. Checking the DESCRIPTION here is
  # what connects the two, and it fails before the ~20 minutes of compiling
  # rather than after.
  desc <- read.dcf(file.path(root, "DESCRIPTION"))
  if (desc[1, "Package"] != spec$pkg || desc[1, "Version"] != spec$version)
    stop(sprintf("commit %s carries %s %s, but this file claims %s %s",
                 substr(spec$sha, 1, 12), desc[1, "Package"], desc[1, "Version"],
                 spec$pkg, spec$version), call. = FALSE)

  # ── Dependencies, from the pinned repositories only ───────────────────────
  # Only the *missing* ones are installed. That is not a speed optimisation: a
  # bare install.packages() on an already-present package replaces it with the
  # snapshot's version whether or not anything asked for that, which is how the
  # numerical chain would move without anyone deciding to move it. Anything
  # already present and satisfying the declared minimum is left alone, and
  # assert_invariants() below is the check that this actually held.
  fields <- intersect(c("Depends", "Imports", "LinkingTo"), colnames(desc))
  dep <- trimws(sub("\\(.*", "", unlist(strsplit(paste(desc[1, fields],
                                                       collapse = ","), ","))))
  dep <- setdiff(dep[nzchar(dep)],
                 c("R", rownames(utils::installed.packages(priority = "base"))))
  need <- setdiff(dep, rownames(utils::installed.packages()))
  cat("dependencies missing before this package:",
      if (length(need)) paste(need, collapse = ", ") else "(none)", "\n")
  if (length(need)) install.packages(need)

  still <- setdiff(dep, rownames(utils::installed.packages()))
  if (length(still))
    stop("dependencies unavailable from the pinned repositories: ",
         paste(still, collapse = ", "),
         "\nAdd them to PKG_PINNED in install-Rpkgs.R if they exist there;",
         "\ndo NOT reach for an unpinned source to satisfy them.", call. = FALSE)

  # repos = NULL is what makes the `Remotes:` field inert -- see the header.
  install.packages(root, repos = NULL, type = "source")

  got <- tryCatch(as.character(utils::packageVersion(spec$pkg)),
                  error = function(e) NA_character_)
  if (is.na(got))
    stop(spec$pkg, " did not install. install.packages() only warns on failure,",
         " so this assertion is the thing that stops a broken image shipping.",
         call. = FALSE)
  if (got != spec$version)
    stop(spec$pkg, " installed as ", got, ", expected ", spec$version, call. = FALSE)

  # Installable is not loadable: a missing system library shows up here, not
  # above. Only runs when this layer is actually built; the per-CI-run check is
  # in .github/workflows/build.yml.
  library(spec$pkg, character.only = TRUE, quietly = TRUE)
  cat(spec$pkg, got, "installed and loadable\n")
}

invisible(lapply(GH_PINNED, install_pinned_github))

assert_invariants("after the GitHub layer")

# ── The databases have to be readable with no network ────────────────────────
# Same reasoning as the annotation-database queries in install-Rpkgs.R: a
# package can attach cleanly and still carry an unusable data object. These are
# cheap versions of the checks in the CI smoke test, kept here on purpose so a
# failure is attributed to this layer rather than to the image as a whole.
db <- CellChat::CellChatDB.human$interaction
stopifnot(is.data.frame(db), nrow(db) > 0,
          all(c("SPP1", "CSF1", "PDGFA") %in% db$ligand))
cat("CellChatDB.human:", nrow(db), "interactions, ships inside the package\n")

# Only the small network here -- the 262 MB ligand-target matrix is read in the
# CI smoke test instead, where the time is spent once per run rather than once
# per build. The md5 check in the Dockerfile already covers all six files.
prior_dir <- Sys.getenv("NICHENET_PRIOR_DIR", "/opt/nichenet")
lr <- readRDS(file.path(prior_dir, "lr_network_human_21122021.rds"))
stopifnot(nrow(lr) > 0, all(c("from", "to") %in% colnames(lr)))
cat("NicheNet lr_network:", nrow(lr), "ligand-receptor edges in", prior_dir, "\n")

# ── Bake the manifest into the image ─────────────────────────────────────────
# Written here rather than in install-Rpkgs.R because this is the last layer to
# touch the library: a manifest written earlier would not list the packages
# installed above. It records the **whole library**, not just what the two
# installers pin: both Bioc and these two packages drag in a chain of
# transitive dependencies, and those are exactly what the assertions do not
# cover. The manifest cannot hold them still, but it can answer afterwards
# "which version was in there". When something breaks, the culprit is usually
# one of the packages nobody named.
bioc <- tryCatch(as.character(BiocManager::version()),
                 error = function(e) "(BiocManager not in the image)")
gh_line <- vapply(GH_PINNED, function(g)
  sprintf("# GitHub: %s %s @ %s", g$pkg, g$version, g$sha), character(1))
ip <- utils::installed.packages()[, c("Package", "Version", "LibPath"), drop = FALSE]
ip <- ip[order(ip[, "Package"]), , drop = FALSE]
writeLines(c("# R package manifest for this image, generated at build time by /opt/install-github-Rpkgs.R",
             paste0("# R: ", R.version.string),
             paste0("# BiocManager: ", bioc),
             paste0("# CRAN: ", getOption("repos")[["CRAN"]]),
             paste0("# Bioc repo: ", getOption("repos")[["BIOC"]]),
             paste0("# Bioc annotation repo: ", getOption("repos")[["BIOCANN"]]),
             gh_line,
             "package\tversion\tlibpath",
             apply(ip, 1, paste, collapse = "\t")),
           "/opt/Renv-manifest.tsv")
cat("manifest written to /opt/Renv-manifest.tsv,", nrow(ip), "packages\n")
