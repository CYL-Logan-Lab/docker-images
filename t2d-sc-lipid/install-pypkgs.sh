#!/bin/sh
# Build the Python environment this image ships (added in v6): a venv at
# /opt/pyenv holding a hash-locked cNMF stack. Run once, from the Dockerfile.
#
# ── Why a venv and not the system interpreter ───────────────────────────────
# The base image is Ubuntu noble, whose python3 is externally managed (PEP 668):
# `pip install` into it refuses to run without --break-system-packages, and the
# flag is refused rather than passed, because it means "overwrite apt's files
# with pip's". A venv is the supported answer and it also keeps the boundary
# legible: every *package* under /opt/pyenv came from requirements-py.txt, which
# pyenv-verify.py asserts in both directions rather than leaving as a
# description of intent.
#
# ── Where the trust in that actually starts, stated exactly ─────────────────
# Creating the venv runs ensurepip, which unpacks a pip wheel from an apt
# package. So the tool that then enforces --require-hashes is itself not one of
# the hashed artifacts: it is trusted the same way curl, libmagick++-dev and the
# rest of this image's userland are, i.e. through apt's signed archive and the
# base image's digest. That bootstrap cannot be removed by pinning pip -- some
# installer has to run first -- and pretending otherwise would be the kind of
# claim this file exists to avoid.
#
# What pinning pip *does* buy is that the bootstrap leaves nothing behind. pip
# is a hashed requirement in requirements-py.txt and the install below passes
# --force-reinstall, so the seeded pip's files are uninstalled and replaced by
# the locked artifact even in the case that would otherwise skip it silently --
# apt happening to ship the same version, where pip would report "already
# satisfied" and leave apt's copy in place. After that the only things in the
# venv that did not come from the lock are venv's own scaffolding: pyvenv.cfg,
# the activate scripts, and the symlinks to the system interpreter.
#
# --force-reinstall is free here, despite reading like a heavy flag: the venv is
# empty apart from the seeded pip, so pip is the only requirement it can
# possibly affect.
#
# ── Why the system interpreter is nonetheless the base ──────────────────────
# The venv inherits /usr/bin/python3, so the interpreter is apt's and only the
# packages are pip's. Building a second Python from source to pin the patch
# version would trade a 3.12.3 -> 3.12.x drift (an ABI-stable security-patch
# move inside one minor version) for a from-source toolchain in every rebuild.
# The minor version is what the cp312 wheels in the lock are matched to, and it
# is asserted below; the patch version is recorded in the manifest.
set -eu

PYENV=/opt/pyenv

# The lock was resolved for one interpreter and one platform: cp312, x86_64,
# manylinux_2_28. Assert all three, not just the interpreter -- on a mismatch pip
# would fail with "no matching distribution", which is true but says nothing
# about why, and the wrong-architecture case (an arm64 runner) is the one where
# that message is most misleading.
#
# manylinux_2_28 is a floor on glibc, so the check is >=, not ==: a newer glibc
# runs those wheels, an older one does not.
/usr/bin/python3 - <<'PY'
import os
import sys
import sysconfig

if sys.version_info[:2] != (3, 12):
    sys.exit(
        "requirements-py.txt is a cp312 lock, but the base image ships Python "
        f"{sys.version.split()[0]}.\nRe-resolve the lock for the new minor "
        "version (see the header of requirements-py.in) rather than deleting "
        "this check."
    )

plat = sysconfig.get_platform()
if plat != "linux-x86_64":
    sys.exit(
        f"requirements-py.txt is an x86_64 lock, but this build is on {plat}.\n"
        "The wheels in it are not portable to another architecture: re-resolve "
        "with the matching --python-platform."
    )

libc = os.confstr("CS_GNU_LIBC_VERSION") or ""      # e.g. "glibc 2.39"
ver = tuple(int(p) for p in libc.split()[-1].split(".")[:2]) if libc else ()
if ver < (2, 28):
    sys.exit(
        f"requirements-py.txt is a manylinux_2_28 lock; this base image has "
        f"{libc or 'an unreported libc'}, which is older. Its wheels will not "
        "load here."
    )
print(f"system python {sys.version.split()[0]} on {plat} with {libc} "
      "-- the cp312 / manylinux_2_28 lock applies")
PY

/usr/bin/python3 -m venv "${PYENV}"

# --require-hashes is the whole point of this layer: pip verifies the sha256 of
# every artifact it downloads against requirements-py.txt and refuses to install
# anything not listed, so the closure that lands here is the one that was
# resolved on a workstation and reviewed in a diff. It also implies "no
# unpinned dependency can sneak in", because pip demands that every requirement
# it resolves carries a hash.
#
# --only-binary=:all: is what actually keeps a compiler out of this image, and
# it is not redundant with the lock's --no-build resolution. `uv pip compile
# --generate-hashes` records a hash for *every* artifact upstream published at
# that version, sdists included, so the lock would happily authorise a source
# archive; --no-build only promised that resolving it did not need to build one.
# This flag is what makes pip refuse the sdist at install time.
#
# --force-reinstall: see the bootstrap note at the top of this file. In an
# otherwise empty venv the only requirement it can affect is the ensurepip-seeded
# pip, which is exactly the one that must not survive on a version match.
#
# --no-cache-dir keeps ~700 MB of wheel cache out of the layer.
# --disable-pip-version-check drops a network round trip to PyPI whose only
# possible outcome is advice to upgrade pip, which this build will not take.
"${PYENV}/bin/pip" install \
    --no-cache-dir --disable-pip-version-check \
    --require-hashes --only-binary=:all: --force-reinstall \
    -r /opt/requirements-py.txt

# Assertions and the manifest live in their own file for the reason the R
# installers do: as a real .py it can be linted and read with syntax
# highlighting, which text embedded in a shell heredoc cannot.
"${PYENV}/bin/python" /opt/pyenv-verify.py

# Same treatment as the R side: the recipe that produced the environment stays
# inside the image, read-only, so a running container can answer "what was I
# built from" without reference to a repository it cannot reach.
chmod 0444 /opt/requirements-py.in /opt/requirements-py.txt \
           /opt/pyenv-verify.py /opt/pyenv-manifest.tsv
chmod 0555 /opt/install-pypkgs.sh
