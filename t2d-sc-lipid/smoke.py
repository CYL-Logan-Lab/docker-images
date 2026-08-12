"""Python half of the smoke test for the t2d-sc-lipid image (added in v6).

Not run directly by the workflow: smoke.R runs it through the venv interpreter
and fails if it exits non-zero or does not print the sentinel below. The reason
for that arrangement rather than a second CI step is in smoke.R -- one entry
point, one sentinel, and an image that ships two runtimes may not report green
on the strength of one of them.

Like the R half, this does not check that packages import. Importing is the
cheapest possible check and it is not the one that catches a broken image: what
matters is whether cNMF **recovers programs that were planted in the data**, so
that is what is asserted. The matrix below has two disjoint gene programs and
two groups of cells built from them; a factorisation into k=2 has one right
answer, known before the run, and the assertions are written against that answer
rather than against whatever the first run happened to produce.

It also exercises the Seurat -> Python bridge the project actually uses (Matrix
Market plus two TSVs, read back with scipy.io.mmread), because a bridge that is
only tested by the analysis that depends on it is not tested.

Everything runs under `docker run --network none` and writes only to a temporary
directory: the script's own directory is a read-only mount.
"""

import os
import sys
import tempfile
from pathlib import Path

import anndata as ad
import numpy as np
import pandas as pd
import scipy.io
import scipy.sparse as sp

# ── The environment is the one the image built, not some other Python ────────
# sys.prefix is the venv, not the interpreter, so this catches "smoke.R found a
# python and it was /usr/bin/python3" -- which would import nothing and fail
# confusingly two hundred lines later.
#
# PYENV_DIR is read here for the same reason smoke.R reads it: the two halves
# must agree on which venv is under test, and a constant on this side would turn
# any override into a confusing assertion failure rather than a working run.
# The default is the image's path, so CI passes nothing.
PYENV = os.environ.get("PYENV_DIR", "/opt/pyenv")
assert sys.prefix == PYENV, f"running under {sys.prefix}, expected {PYENV}"
assert sys.version_info[:2] == (3, 12), f"expected cp312, got {sys.version}"
assert Path("/opt/pyenv-manifest.tsv").is_file(), "the venv layer left no manifest"

# ── A matrix with a known answer ─────────────────────────────────────────────
# 240 cells, 150 genes. Genes 0-29 are program A, genes 30-59 are program B, the
# remaining 90 are background expressed by everything. Cells 0-119 run program
# A, cells 120-239 run program B. The two programs share no genes, so a k=2
# factorisation that does not return them has got it wrong.
#
# Poisson counts from a seeded Generator rather than a fixed integer matrix:
# cNMF selects high-variance genes before factorising, and a matrix with no
# sampling noise gives that step nothing to rank. numpy guarantees the PCG64
# stream, so "seeded" here means reproducible across versions, not merely
# within one run.
N_CELLS, N_GENES = 240, 150
PROG_A = np.arange(0, 30)
PROG_B = np.arange(30, 60)
rng = np.random.default_rng(20260812)

lam = np.full((N_CELLS, N_GENES), 2.0)          # background everything expresses
lam[:120, PROG_A] += 30.0                        # group 1 runs program A
lam[120:, PROG_B] += 30.0                        # group 2 runs program B
counts = rng.poisson(lam).astype(np.int32)

cells = [f"cell{i:03d}" for i in range(N_CELLS)]
genes = [f"gene{j:03d}" for j in range(N_GENES)]
truth = np.array([0] * 120 + [1] * 120)          # which program each cell runs

# ── The bridge: Matrix Market out, AnnData in ────────────────────────────────
# This is how nuclei will cross from Seurat into cNMF -- not through
# zellkonverter/basilisk, which downloads a conda environment at first use (see
# requirements-py.in). Writing the mtx here with scipy and reading it back with
# scipy is only half the round trip that the analysis does, but it is the half
# that lives in this image; the R half is Matrix::writeMM, whose output format
# is the same file this reads.
tmp = tempfile.TemporaryDirectory()
work = Path(tmp.name)
scipy.io.mmwrite(str(work / "counts.mtx"), sp.csr_matrix(counts))
pd.Series(cells).to_csv(work / "cells.tsv", sep="\t", index=False, header=False)
pd.Series(genes).to_csv(work / "genes.tsv", sep="\t", index=False, header=False)

# csr_matrix() around mmread() rather than .tocsr() on its result: scipy is
# changing what mmread returns (spmatrix today, sparray in 1.20), and the two
# differ in `@` versus `*` semantics. Constructing the type explicitly means this
# line keeps meaning the same thing when that default flips, and it is also the
# type AnnData wants.
mm = sp.csr_matrix(scipy.io.mmread(str(work / "counts.mtx")))
obs = pd.read_csv(work / "cells.tsv", sep="\t", header=None)[0].tolist()
var = pd.read_csv(work / "genes.tsv", sep="\t", header=None)[0].tolist()
assert mm.shape == (N_CELLS, N_GENES), f"round trip changed the shape: {mm.shape}"
assert (mm.toarray() == counts).all(), "round trip changed the counts"
assert obs == cells and var == genes, "round trip changed the names"

adata = ad.AnnData(
    X=mm,
    obs=pd.DataFrame(index=pd.Index(obs, name=None)),
    var=pd.DataFrame(index=pd.Index(var, name=None)),
)
h5ad = work / "counts.h5ad"
adata.write_h5ad(h5ad)                            # h5py, and the format cnmf reads
back = ad.read_h5ad(h5ad)
assert back.shape == adata.shape, "h5ad round trip changed the shape"
assert (back.X.toarray() == counts).all(), "h5ad round trip changed the counts"

# ── cNMF, end to end ─────────────────────────────────────────────────────────
# Imported here rather than at the top so that the two checks above -- which do
# not need it -- report first if the environment is wrong.
#
# n_iter=5 rather than the 100 an analysis would use: the consensus over
# replicates is what is being exercised, not its stability at scale, and five
# replicates is enough for the clustering step to have something to cluster.
# density_threshold=2.0 disables outlier filtering, which is what the method's
# own documentation says that value means; filtering here would make the test
# depend on the spread of five toy replicates.
from cnmf import cNMF  # noqa: E402

K = 2
run = cNMF(output_dir=str(work / "cnmf"), name="smoke")
run.prepare(counts_fn=str(h5ad), components=[K], n_iter=5, seed=20260812,
            num_highvar_genes=100)
run.factorize(worker_i=0, total_workers=1)
run.combine()
run.consensus(k=K, density_threshold=2.0, show_clustering=True,
              close_clustergram_fig=True)
usage, spectra_scores, spectra_tpm, top_genes = run.load_results(
    K=K, density_threshold=2.0, n_top_genes=20)

assert usage.shape == (N_CELLS, K), f"usage is {usage.shape}, expected {(N_CELLS, K)}"
assert not usage.isna().any().any(), "usage has missing values"

# Which factor is which is arbitrary -- NMF does not order its components -- so
# the assertion is on the partition, not on the labels. Every cell is assigned
# to its dominant factor; the assignment must agree with the planted grouping
# either as-is or with the two labels swapped.
assigned = usage.to_numpy().argmax(axis=1)
agree = max((assigned == truth).mean(), (assigned == 1 - truth).mean())
assert agree > 0.95, f"usage recovers the planted grouping for only {agree:.1%} of cells"

# And the programs themselves: the factor that group 1 runs must be built from
# program A's genes and nothing else. 20 top genes, at least 18 from the right
# set -- not 20/20, because two disjoint programs in Poisson counts leave a
# little room at the bottom of the ranking, and a test that demands perfection
# gets deleted the first time it is merely very good.
factor_of_group1 = assigned[:120]
f1 = int(np.bincount(factor_of_group1, minlength=K).argmax())
f2 = 1 - f1
names_a = {f"gene{j:03d}" for j in PROG_A}
names_b = {f"gene{j:03d}" for j in PROG_B}
# Positional rather than by column name: load_results casts the usage columns to
# int and leaves the spectra columns as they were read, so the two frames can
# disagree on the *type* of the label while agreeing on the order (both are the
# k factors in ascending order). Position is the thing that is actually shared.
hit_a = sum(g in names_a for g in top_genes.iloc[:, f1])
hit_b = sum(g in names_b for g in top_genes.iloc[:, f2])
assert hit_a >= 18, f"factor for group 1 has only {hit_a}/20 program-A genes"
assert hit_b >= 18, f"factor for group 2 has only {hit_b}/20 program-B genes"

# The consensus step draws its clustergram with matplotlib. Asserting the file
# is on disk and not empty is what makes "matplotlib works headless in this
# image" a checked claim rather than an assumption about MPLBACKEND.
figs = sorted((work / "cnmf" / "smoke").glob("*.png"))
assert figs, "consensus produced no clustergram"
assert all(f.stat().st_size > 1024 for f in figs), "clustergram is empty"

# Versions from the installed distribution metadata rather than from each
# package's __version__ attribute: anndata and scanpy both deprecated theirs and
# emit a FutureWarning when it is read, and the metadata is the more honest
# source anyway -- it is what pip recorded when it installed the wheel, which is
# the thing requirements-py.txt pinned. Distribution names, not module names, so
# scikit-learn is spelled with the hyphen here.
from importlib.metadata import version as dist_version  # noqa: E402

print(
    f"python ok: {sys.version.split()[0]}"
    f" / cnmf {dist_version('cnmf')}"
    f" / anndata {dist_version('anndata')} / scanpy {dist_version('scanpy')}"
    f" / scikit-learn {dist_version('scikit-learn')}"
    f" / numpy {dist_version('numpy')} / pandas {dist_version('pandas')}"
    f" / planted 2 programs in {N_CELLS}x{N_GENES}, recovered grouping"
    f" {agree:.0%}, top-20 genes {hit_a}/20 and {hit_b}/20,"
    f" {len(figs)} clustergram(s), mtx and h5ad round trips exact"
)
tmp.cleanup()
