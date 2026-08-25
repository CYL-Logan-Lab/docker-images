#!/usr/bin/env bash
# Build BAFExtract from a pinned commit.
#
# BAFExtract derives B-allele frequency shifts from mapped reads without a
# variant call set. It reads a SAM stream and treats it as one sample: it has no
# cell-barcode awareness. For 10x data the caller must therefore split the BAM by
# barcode group before piping it here, which is done in the analysis stage rather
# than in this image.

set -euo pipefail

: "${BAFEXTRACT_REPO:?BAFEXTRACT_REPO is not set}"
: "${BAFEXTRACT_COMMIT:?BAFEXTRACT_COMMIT is not set}"

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "${BUILD_DIR}"' EXIT

git clone --quiet "${BAFEXTRACT_REPO}" "${BUILD_DIR}/BAFExtract"
cd "${BUILD_DIR}/BAFExtract"
git checkout --quiet "${BAFEXTRACT_COMMIT}"
observed=$(git rev-parse HEAD)
if [[ "${observed}" != "${BAFEXTRACT_COMMIT}" ]]; then
  echo "BAFExtract commit mismatch: ${observed}" >&2
  exit 1
fi

make >/dev/null

if [[ -x bin/BAFExtract ]]; then
  install -m 0755 bin/BAFExtract /usr/local/bin/BAFExtract
elif [[ -x BAFExtract ]]; then
  install -m 0755 BAFExtract /usr/local/bin/BAFExtract
else
  echo "BAFExtract binary was not produced by make" >&2
  find . -maxdepth 2 -type f -perm -u+x >&2
  exit 1
fi

mkdir -p /opt/pitnets-cnv
printf 'tool\tcommit\n' > /opt/pitnets-cnv/baf-tool-versions.tsv
printf 'BAFExtract\t%s\n' "${BAFEXTRACT_COMMIT}" >> /opt/pitnets-cnv/baf-tool-versions.tsv

# The binary prints usage and exits non-zero when called without arguments, so
# only check that it runs and produces its own usage text.
if ! /usr/local/bin/BAFExtract 2>&1 | grep -qi 'BAFExtract\|USAGE\|Usage\|options'; then
  echo "BAFExtract did not produce usage output" >&2
  exit 1
fi

echo "BAFExtract installed at commit ${BAFEXTRACT_COMMIT}"
