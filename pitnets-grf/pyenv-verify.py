"""Verify the Python environment this image ships, and bake its manifest.

Run by install-pypkgs.sh as the last thing in the Python layer, with the venv's
own interpreter. It is the Python counterpart of the assertion block at the
bottom of install-Rpkgs.R, and it exists for the same reason: an installer that
only *warns* on failure will happily produce an image that ships broken.

Four checks, in the order a failure is cheapest to read:

  1. requirements-py.in and requirements-py.txt describe the same direct
     requirements at the same versions -- in both directions, using uv's `# via`
     annotations to recover which pins the lock considers direct, so that a pin
     *removed* from the .in without re-resolving fails too and not only a pin
     added;
  2. the installed set and the lock are the same set, at the same versions --
     in both directions, so a partial install fails and so does anything that
     reached the venv without going through the lock;
  3. `pip check` -- the resolved closure is internally consistent;
  4. every direct pin imports, because installable does not mean importable when
     a compiled wheel disagrees with the interpreter it landed on.

Check 2 covers the whole lock rather than only the pins written by hand, and
that is the point: the argument for this layer is that the *transitive* closure
is pinned, and an assertion that only reads the hand-written names would leave
exactly that claim unchecked.

Then it writes /opt/pitnets-pyenv-manifest.tsv, which lists the whole environment --
same role as /opt/Renv-manifest.tsv on the R side. Unlike that one it is not the
only record of the transitive set (requirements-py.txt pins those too, with
hashes), so read it as the as-built confirmation rather than as the only
evidence. Its header records the interpreter's full version, which the lock does
not pin: see the apt note in the Dockerfile.
"""

import importlib
import importlib.metadata as md
import hashlib
import os
import re
import subprocess
import sys

from packaging.version import InvalidVersion, Version

REQ_IN = "/opt/pitnets-grf/requirements-py.in"
LOCK = "/opt/pitnets-grf/requirements-py.txt"
MANIFEST = "/opt/pitnets-pyenv-manifest.tsv"

# Distribution name -> module name, for the two that differ. Anything not listed
# imports under its own name. Kept as a table rather than a heuristic: guessing
# the module name from the distribution name is exactly the kind of rule that
# works for eleven packages and then silently skips the twelfth.
MODULE = {
    "adjustText": "adjustText",
    "scikit-learn": "sklearn",
    "PyYAML": "yaml",
}

# `pandas` and friends are spelled inconsistently across metadata (PyYAML vs
# pyyaml, scikit-learn vs scikit_learn). PyPA normalisation is the rule that
# resolves it; implement it rather than lowercasing and hoping.
def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def same_version(a, b):
    """Compare as versions, not as strings: `1.5` and `1.5.0` are one release."""
    if a is None or b is None:
        return False
    try:
        return Version(a) == Version(b)
    except InvalidVersion:
        return a == b


def parse_pins(path):
    """Read `name==version` lines into {normalised name: (as written, version)}.

    Handles both files: requirements-py.in is plain `name==version` with
    comments, and the lock adds a trailing backslash plus indented `--hash=`
    continuation lines, which start with `-` and are skipped.
    """
    pins = {}
    with open(path) as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip().rstrip("\\").strip()
            if not line or line.startswith("-"):
                continue
            if "==" not in line:
                sys.exit(f"{path}: cannot read this as a pin: {line!r}")
            name, version = line.split("==", 1)
            pins[norm(name.strip())] = (name.strip(), version.strip())
    if not pins:
        sys.exit(f"{path}: no pins found -- refusing to verify nothing")
    return pins


def parse_lock_roots(path):
    """Which packages the lock says came from the .in, per uv's `# via` notes.

    uv annotates every pin with what required it, either inline
    (`# via -r requirements-py.in`) or as an indented list under a bare
    `# via`. A pin carrying that annotation is a direct requirement; one whose
    annotation names only other packages is transitive. Reading them back is
    what makes the .in/lock comparison work in both directions -- without it a
    pin *deleted* from the .in leaves no trace, because the lock still has it
    and everything downstream still agrees with the lock.

    This does read a comment, so a future uv that annotates differently would
    stop finding roots -- in which case every direct pin is reported as missing
    and the build fails saying so, which is the right direction to fail in.
    """
    basename = os.path.basename(REQ_IN)
    roots, cur = set(), None
    with open(path) as fh:
        for line in fh:
            stripped = line.strip()
            if not stripped.startswith("#") and "==" in stripped:
                cur = norm(stripped.split("==", 1)[0].strip())
            elif stripped.startswith("#") and cur is not None:
                body = stripped.lstrip("#").strip()
                if body.startswith("via "):
                    body = body[4:].strip()
                if body.startswith("-r ") and \
                        os.path.basename(body[3:].strip()) == basename:
                    roots.add(cur)
    return roots


def main():
    direct = parse_pins(REQ_IN)
    locked = parse_pins(LOCK)
    roots = parse_lock_roots(LOCK)

    # 1. the lock is downstream of the .in, so drift between them is an editing
    #    mistake that would otherwise install versions nobody asked for. Both
    #    directions: a pin added to the .in without re-resolving is caught by
    #    its absence from the lock, and a pin *removed* from the .in is caught by
    #    the lock still listing it as a direct root -- that one is otherwise
    #    invisible, since the package stays installed and every later check
    #    compares against the lock and passes.
    drift = [
        f"  {raw:<14} .in says {want:<9} lock says "
        f"{locked[n][1] if n in locked else '<absent from lock>'}"
        for n, (raw, want) in direct.items()
        if n not in locked or not same_version(locked[n][1], want)
    ]
    drift += [
        f"  {locked[n][0]:<14} not in the .in, but the lock records it as "
        "coming from there"
        for n in sorted(roots - set(direct))
    ]
    # A pin present in both files but no longer marked as a root would mean the
    # lock was resolved from a different .in than this one.
    drift += [
        f"  {raw:<14} is in the .in, but the lock does not record it as coming "
        "from there"
        for n, (raw, _want) in sorted(direct.items())
        if n in locked and n not in roots
    ]
    if drift:
        sys.exit(
            "requirements-py.in and requirements-py.txt disagree:\n"
            + "\n".join(drift)
            + "\n\nRegenerate the lock and commit both files together:\n"
            "  uv pip compile requirements-py.in --python-version 3.12 \\\n"
            "      --python-platform x86_64-manylinux_2_28 --generate-hashes \\\n"
            "      --no-build -o requirements-py.txt"
        )

    # 2. what is installed must be exactly what the lock said -- the *whole*
    #    lock, not just the pins written by hand. Checking only the direct pins
    #    would leave the claim this layer is built on ("the transitive closure is
    #    pinned too") asserted nowhere: a partial install that stopped after the
    #    twelve named packages would pass, and so would an environment in which a
    #    transitive dependency landed at a version the lock does not name.
    installed = {}
    for d in md.distributions():
        name = d.metadata["Name"]
        if name:                       # a broken .dist-info can have none
            installed[norm(name)] = (name, d.version)

    bad = []
    for n, (raw, want) in sorted(locked.items()):
        got = installed.get(n, (None, None))[1]
        if not same_version(got, want):
            bad.append(f"  {raw:<24} expected {want:<10} got "
                       f"{got or '<not installed>'}")
    # And nothing may be installed that the lock does not list. This is the check
    # that catches the venv's own seeding: `python3 -m venv` runs ensurepip,
    # which unpacks pip (and, on Pythons before 3.12, setuptools and wheel) from
    # apt's wheel packages rather than from the lock. pip is in the lock and is
    # therefore replaced by the pinned one during the install; anything else that
    # turns up here arrived from outside every pin in this repository and is
    # reported rather than tolerated.
    extra = [f"  {raw} {ver}" for n, (raw, ver) in sorted(installed.items())
             if n not in locked]
    if bad or extra:
        sys.exit(
            "the installed environment disagrees with requirements-py.txt:\n"
            + ("\n".join(bad) if bad else "")
            + (("\nnot in the lock at all:\n" + "\n".join(extra)) if extra else "")
            + "\n\nUpstream moved, the install was partial, or something reached"
            "\nthis venv without going through the lock. Do not delete this"
            "\nassertion: fix the pin, regenerate the lock, rebuild."
        )

    # 3. pip's own consistency check catches the case the hashes cannot: a
    #    closure where two packages each installed fine and declare requirements
    #    the other violates.
    check = subprocess.run([sys.executable, "-m", "pip", "check"],
                           capture_output=True, text=True)
    if check.returncode != 0:
        sys.exit("pip check failed:\n" + check.stdout + check.stderr)

    # 4. import, not just install. A manylinux wheel that disagrees with the
    #    interpreter installs without complaint and fails at the first import,
    #    which is a runtime this build is meant to move to build time.
    for _, (raw, _want) in sorted(direct.items()):
        mod = MODULE.get(raw, raw)
        try:
            importlib.import_module(mod)
        except Exception as exc:  # noqa: BLE001 -- the point is to report any of them
            sys.exit(f"{raw} installed but `import {mod}` failed: {exc!r}")

    # The manifest. The lock's sha256 goes in the header so a built image can be
    # matched back to the exact resolution it came from, without trusting that
    # the recipe in git was never amended.
    with open(LOCK, "rb") as fh:
        lock_sha = hashlib.sha256(fh.read()).hexdigest()
    dists = [installed[n] for n in sorted(installed)]
    with open(MANIFEST, "w") as fh:
        fh.write(
            "# Python package manifest for this image, generated at build time "
            "by /opt/pitnets-grf/pyenv-verify.py\n"
            f"# python: {sys.version.split()[0]} ({sys.executable})\n"
            f"# pip: {md.version('pip')}\n"
            f"# lock: {LOCK} sha256:{lock_sha}\n"
            "package\tversion\n"
        )
        for name, version in dists:
            fh.write(f"{name}\t{version}\n")

    print(f"python env intact: {len(direct)} direct pins, {len(locked)} locked, "
          f"{len(dists)} installed and every one of them accounted for; "
          f"manifest written to {MANIFEST}")


if __name__ == "__main__":
    main()
