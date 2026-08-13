# docker-images

Computational environment recipes for CYL-Logan-Lab projects.
**One project, one directory, one Dockerfile inside it.** The directory name
matches the project's repository name, so the correspondence is obvious.

Images are built by GitHub Actions and pushed to GHCR (public, no login needed
to pull):

```
ghcr.io/cyl-logan-lab/<directory>
```

| Directory | Used by | Contents |
|---|---|---|
| [`pitnets-grf/`](pitnets-grf/Dockerfile) | PitNETs_GRF | Downstream scRNA-seq + spatial transcriptomics + bulk RNA-seq + Nanopore DRS result analysis: Seurat/Scanpy/SpatialData, DESeq2/edgeR/limma, isoform-switch and genomic-range tooling, plus publication graphics; no Cell Ranger, basecaller or aligner |
| [`t2d-sc-lipid/`](t2d-sc-lipid/Dockerfile) | [CYL-Logan-Lab/t2d-sc-lipid](https://github.com/CYL-Logan-Lab/t2d-sc-lipid) | R 4.5.2 / Seurat 5.5.1 / Bioconductor 3.22 + scDblFinder + clusterProfiler/ReactomePA + CellChat/nichenetr + hdWGCNA/UCell/GSVA + decoupleR/dorothea + slingshot + limma/metafor, all databases offline; plus a hash-locked Python 3.12 venv at `/opt/pyenv` for cNMF |
| [`t2d-meta-lipid/`](t2d-meta-lipid/Dockerfile) | [CYL-Logan-Lab/t2d-adipose-depot-dysfunction](https://github.com/CYL-Logan-Lab/t2d-adipose-depot-dysfunction) | R 4.5.2 / coloc 6.0.1 / jsonlite 2.0.0 / curl 8.5.0 |

## How downstream projects reference an image

**By digest, not by tag.** A tag is a mutable reference — once the same tag is
re-pushed you get a different image with no warning. A digest is
content-addressed and cannot change. `:latest` exists only to show a human which
image is the newest; it is not how you pin an environment.

The digest appears in the job summary of every publishing build (Actions → that
run → Summary), and can also be read directly:

```bash
docker buildx imagetools inspect ghcr.io/cyl-logan-lab/t2d-sc-lipid:latest
```

Pulling:

```bash
docker pull ghcr.io/cyl-logan-lab/t2d-sc-lipid@sha256:<digest>

# On machines without docker permissions, use Singularity/Apptainer
# (GHCR is public here, so no login is required)
singularity pull env.sif docker://ghcr.io/cyl-logan-lab/t2d-sc-lipid@sha256:<digest>
```

Then write that digest into the downstream project's own environment script and
verify it there.

## The limits of reproducibility, stated up front

**The unit of reproducibility is the image that was produced, not "rebuild and
get the same thing".** Downstream pins by digest, so "which environment did this
analysis actually run in" always has an exact answer. A recipe's job is to make
the image buildable and to make the built image match its own claims.

Concretely: direct dependencies have per-package version assertions and a
mismatch fails the build; but the **transitive** dependencies that Bioconductor
drags in are not pinned. Their patch versions can drift without failing the
build, and the drift is only visible in `/opt/Renv-manifest.tsv` inside the
image. So rebuilding the same recipe six months later **may** yield a slightly
different environment — which is exactly why downstream must reference the
digest instead of "building its own from the recipe".

## Five pinning layers

Every Dockerfile has to answer "what is this environment" on its own. A recipe
missing one of these layers only says "roughly these packages":

1. **Base image taken by digest**, not by tag; and the install script
   **asserts** the R / Seurat versions — a claim stated in prose at the top of
   the file should be executable.
2. **CRAN through a date-frozen snapshot** (Posit Package Manager), never a
   rolling mirror.
3. **Bioconductor has no dated snapshot service.** The version is nailed down by
   the release-branch URL, but that branch keeps rolling out patch versions — so
   every direct dependency gets an **explicit version assertion** and a mismatch
   fails the build. A failed assertion means upstream moved: write the new
   version into the recipe and rebuild, **do not** delete the assertion.
4. **GitHub-only packages by commit SHA**, never by tag or branch — a tag can be
   repointed at different code with nothing visible changing in the recipe, and
   a SHA cannot. Fetch the archive by SHA (not `remotes::install_github`, which
   needs a rate-limited API call and, worse, honours the `Remotes:` field —
   which installs *further* packages from GitHub HEAD, unpinned by
   construction), then check the DESCRIPTION says the claimed version *before*
   installing. Dependencies come from layers 2 and 3 only; one that is not
   available there fails the build instead of being fetched from somewhere
   unpinned.

   Reach for this layer only when a package is on neither CRAN nor
   Bioconductor. It is the weakest of the five: nothing upstream promises the
   repository will still exist.
5. **PyPI as a hash-locked closure**, when an image needs Python as well. Direct
   pins are written by hand (`requirements-py.in`) and resolved once into a lock
   carrying a sha256 for every artifact in the transitive closure
   (`requirements-py.txt`); the build installs it with `--require-hashes
   --only-binary=:all:` into a venv, so pip refuses anything not listed and
   refuses any source distribution. This is the **strongest** layer here, and
   worth saying plainly because layer 3 is the weakest: a Bioconductor
   release-branch URL pins the direct dependencies by assertion and lets their
   transitive closure drift, whereas re-running this layer either installs
   artifacts whose sha256 the lock already named or fails outright. State the
   guarantee precisely, though — the lock authorises a *set* of artifacts per
   distribution (every wheel upstream published for that version, and the source
   archive), and it is the platform and interpreter that pick one member of it:
   `cp312`, `x86_64`, `glibc >= 2.28`, all three asserted before the install
   runs. The interpreter itself comes from apt, and so does the bootstrap pip
   that executes the install, so it is the packages that repeat byte for byte,
   not the whole environment. `--only-binary=:all:` at install time is what makes
   the closure wheel-only, and therefore what lets the image ship no compiler;
   resolving with `--no-build` guarantees the resolution never needed one.

   `t2d-sc-lipid` is the only image using this so far, for cNMF.

Four further conventions:

- **The smoke test lives outside the Dockerfile**, run by CI with `docker run`
  against the image that build actually produced. As a layer inside the image it
  would be useless: a cache hit skips the whole layer, so the build would not
  have run a single R process while still looking "verified". A publishing build
  pulls the image back by digest, so the pushed artifact itself is what gets
  tested. CI mounts the image's whole directory read-only and runs `smoke.R`
  from it; an image shipping a second runtime puts its test beside that file and
  `smoke.R` drives it, so there is one entry point and one sentinel. Two
  sentinels would be worse, not better — they can go green one at a time.
- **Bake the package manifest into the image** (`/opt/Renv-manifest.tsv`),
  recording the whole library rather than just the named packages — for the
  transitive dependencies the assertions cannot cover, this at least answers
  afterwards which version was in there. Write it in the **last** install layer,
  or it will not list what the later layers installed.
- **A reference database that a package fetches at run time is not pinned by any
  of the layers above** — the result then depends on the day the analysis ran.
  Prefer packages that ship their databases (`org.Hs.eg.db`, `reactome.db`,
  `CellChatDB`); when the data is distributed separately, download it *into the
  image* from an immutable archive and verify a checksum (NicheNet's prior
  networks come from a Zenodo record this way). Put that download **before** the
  R layers so that editing an installer does not re-fetch hundreds of megabytes.
  This criterion decides package choices, not just build steps: `liana` and
  `SingleCellSignalR` were both dropped from `t2d-sc-lipid` for failing it, and
  the reasons are recorded next to where each would have been installed.
- **Adding packages must not move the ones already there.** `install.packages()`
  silently upgrades an installed package whenever some new dependency declares a
  higher minimum, and the numerical libraries under an existing analysis
  (`Matrix`, `irlba`, …) are exactly what must not move. So: install only the
  *missing* dependencies, and assert afterwards that the named versions are
  unchanged (`t2d-sc-lipid/Rlib-invariants.R`). Downstream asserts the six it
  calls by name when it pulls the image; the image additionally holds the
  numerical libraries underneath those, which nothing downstream names. Failing
  at build time is one line in a CI log, failing after publishing is a retracted
  digest.

## Adding a new environment

1. Create a directory named after the downstream project's repository (lowercase
   letters and digits only, with `.` `_` `-` as separators — CI enforces this,
   and a GHCR repository path must be lowercase).
2. Write `<directory>/Dockerfile` following the pinning layers in
   `t2d-sc-lipid/Dockerfile`.
3. Add a row to the table above.
4. Open a PR — CI builds it and runs the smoke test, but does not push. Only a
   merge to `main` publishes to GHCR.

To rebuild one image by hand: Actions → build → Run workflow, and give the
directory name (empty builds all). **A manual run never publishes**, it only
validates the recipe — otherwise one click on a feature branch would push
unmerged work to GHCR and overwrite `:latest`.

## When CI builds

- A file changed inside an image directory → only that directory is built.
- Anything under `.github/` changed → everything is rebuilt (the build procedure
  itself changed, so every image is affected).
- First push on a branch, or no comparable baseline → everything is rebuilt
  (better to build all than to silently skip something).

Publishing to GHCR **only happens on a push to `main`**. Pull requests and
manual runs build without pushing.
