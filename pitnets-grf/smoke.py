import tempfile
from pathlib import Path

import anndata as ad
import gffutils
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import pysam
import scanpy as sc
import seaborn as sns
import spatialdata

rng = np.random.default_rng(7)
counts = rng.poisson(3, size=(24, 40)).astype(np.float32)
adata = ad.AnnData(counts)
adata.obs["sample"] = np.repeat(["P1", "P2"], 12)
adata.obsm["spatial"] = rng.uniform(0, 100, size=(24, 2))
sc.pp.normalize_total(adata)
sc.pp.log1p(adata)
sc.pp.pca(adata, n_comps=8)
sc.pp.neighbors(adata, n_neighbors=5, n_pcs=8)
assert adata.obsm["X_pca"].shape == (24, 8)
assert adata.obsm["spatial"].shape == (24, 2)

with tempfile.TemporaryDirectory() as directory:
    directory = Path(directory)
    h5ad = directory / "pitnets.h5ad"
    parquet = directory / "drs-results.parquet"
    figure = directory / "embedding.png"
    gff = directory / "isoforms.gff3"
    database = directory / "isoforms.db"

    adata.write_h5ad(h5ad)
    assert ad.read_h5ad(h5ad).shape == adata.shape

    table = pa.Table.from_pandas(pd.DataFrame({
        "transcript_id": ["tx1", "tx2"],
        "gene_id": ["gene1", "gene1"],
        "count": [12, 8],
    }))
    pq.write_table(table, parquet)
    assert pq.read_table(parquet).num_rows == 2

    gff.write_text(
        "##gff-version 3\n"
        "chr1\ttest\tgene\t1\t1000\t.\t+\t.\tID=gene1\n"
        "chr1\ttest\tmRNA\t1\t1000\t.\t+\t.\tID=tx1;Parent=gene1\n"
        "chr1\ttest\texon\t1\t100\t.\t+\t.\tID=ex1;Parent=tx1\n"
    )
    db = gffutils.create_db(str(gff), dbfn=str(database), force=True,
                            keep_order=True, merge_strategy="merge")
    assert db["tx1"].attributes["Parent"] == ["gene1"]

    header = pysam.AlignmentHeader.from_dict({"SQ": [{"SN": "chr1", "LN": 1000}]})
    assert header.get_reference_name(0) == "chr1"

    sns.scatterplot(x=adata.obsm["X_pca"][:, 0],
                    y=adata.obsm["X_pca"][:, 1], hue=adata.obs["sample"])
    plt.savefig(figure, dpi=100)
    plt.close()
    assert figure.stat().st_size > 0

assert spatialdata.__version__ == "0.8.0"
print("python smoke ok: Scanpy/SpatialData/AnnData, DRS tables, GFF/BAM APIs and plotting")
