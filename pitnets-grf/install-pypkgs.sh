#!/bin/sh
set -eu

PYENV=/opt/pitnets-pyenv

/usr/bin/python3 - <<'PY'
import os
import sys
import sysconfig

if sys.version_info[:2] != (3, 12):
    sys.exit(f"expected Python 3.12, got {sys.version.split()[0]}")
if sysconfig.get_platform() != "linux-x86_64":
    sys.exit(f"the lock targets linux-x86_64, got {sysconfig.get_platform()}")
libc = os.confstr("CS_GNU_LIBC_VERSION") or ""
version = tuple(int(part) for part in libc.split()[-1].split(".")[:2]) if libc else ()
if version < (2, 28):
    sys.exit(f"the lock requires glibc >= 2.28, got {libc or 'unknown'}")
PY

/usr/bin/python3 -m venv "${PYENV}"
"${PYENV}/bin/python" -m pip install \
  --require-hashes \
  --only-binary=:all: \
  --force-reinstall \
  -r /opt/pitnets-grf/requirements-py.txt
"${PYENV}/bin/python" /opt/pitnets-grf/pyenv-verify.py
