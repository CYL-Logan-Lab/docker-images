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
| [`t2d-sc-lipid/`](t2d-sc-lipid/Dockerfile) | [CYL-Logan-Lab/t2d-sc-lipid](https://github.com/CYL-Logan-Lab/t2d-sc-lipid) | R 4.5.2 / Seurat 5.5.1 / Bioconductor 3.22 + scDblFinder |

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

## Three pinning layers

Every Dockerfile has to answer "what is this environment" on its own. A recipe
without all three layers only says "roughly these packages":

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

Two further conventions:

- **The smoke test lives outside the Dockerfile**, run by CI with `docker run`
  against the image that build actually produced. As a layer inside the image it
  would be useless: a cache hit skips the whole layer, so the build would not
  have run a single R process while still looking "verified". A publishing build
  pulls the image back by digest, so the pushed artifact itself is what gets
  tested.
- **Bake the package manifest into the image** (`/opt/Renv-manifest.tsv`),
  recording the whole library rather than just the named packages — for the
  transitive dependencies the assertions cannot cover, this at least answers
  afterwards which version was in there.

## Adding a new environment

1. Create a directory named after the downstream project's repository (lowercase
   letters and digits only, with `.` `_` `-` as separators — CI enforces this,
   and a GHCR repository path must be lowercase).
2. Write `<directory>/Dockerfile` following the three pinning layers in
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
