#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the package's source tarball, byte-reproducibly.

Output: dist/NAME-VERSION.tar and .sha256 (or --out DIR). The tarball is what
packaging/arch/PKGBUILD pins, so it has to be the same bytes every time it is
built from the same inputs.

Contents, under NAME-VERSION/, laid out as in the repository so the root
Makefile's `install` target works in both places:

  src/macbook91-wireless/   every tracked file, plus, for every series listed
                            in its KERNEL-SERIES, exactly the files listed in
                            series/<S>/UPSTREAM.sha256 (written by
                            packaging/fetch-upstream.sh after checking them
                            against packaging/upstream.lock) and that manifest
                            with its companions
  tools/macbook91-wireless-verify, tools/kernel-series and the pacman hook
  next to it, Makefile, VERSION, LICENSE, the license
  texts in LICENSES/, README.md

Anything else in the module tree that git does not track and that is not a
build artifact is refused, so an unknown file never reaches /usr/src unseen.
So is a tree that is not assembled, and - unless --allow-dirty - a tracked
file with uncommitted changes.

Entries are sorted, owned by 0:0, mode 0755 for executables and 0644
otherwise, all with mtime 0, and the tar is not compressed (compressor output
differs between implementations). Same scheme as macbook91-cs4208.
"""

from __future__ import annotations

import fnmatch
import hashlib
import io
import os
import subprocess
import sys
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "macbook91-wireless-dkms"
MODULE = "src/macbook91-wireless"
# Module-root companions of the series trees under series/<S>/ (whose own
# companions are listed in the series' UPSTREAM.sha256 and in SERIES_COMPANIONS).
COMPANIONS = ("UPSTREAM.lock", "KERNEL-SERIES")
SERIES_COMPANIONS = ("UPSTREAM.sha256", "KERNEL-SERIES", "KERNEL-TAG")
ARTIFACTS = ("*.o", "*.ko", "*.mod", "*.mod.c", "*.symvers", "*.order", ".*.cmd", "*.a", ".tmp_versions/*")
EXTRA = (
    "tools/macbook91-wireless-verify", "tools/kernel-series",
    "tools/macbook91-wireless-series.hook", "Makefile", "VERSION", "LICENSE",
    "LICENSES/GPL-2.0-only.txt", "LICENSES/GPL-2.0-or-later.txt", "LICENSES/ISC",
    "LICENSES/MIT", "README.md",
)


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True, text=True).stdout


def fail(msg: str) -> int:
    print(f"mkdist: {msg}", file=sys.stderr)
    return 1


def generated() -> list[str] | None:
    """Generated files of the module tree, relative to it: the series list and
    lock lines, and for each series its manifest, companions and listed files."""
    base = os.path.join(ROOT, MODULE)
    if not all(os.path.isfile(os.path.join(base, c)) for c in COMPANIONS):
        return None
    with open(os.path.join(base, "KERNEL-SERIES"), encoding="utf-8") as fh:
        series = [line.strip() for line in fh if line.strip()]
    if not series:
        return None
    out = set(COMPANIONS)
    for s in series:
        manifest = os.path.join(base, "series", s, "UPSTREAM.sha256")
        if not os.path.isfile(manifest):
            return None
        with open(manifest, encoding="utf-8") as fh:
            listed = [line.split("  ", 1)[1].rstrip("\n") for line in fh if line.strip()]
        out |= {f"series/{s}/{f}" for f in listed}
        out |= {f"series/{s}/{c}" for c in SERIES_COMPANIONS}
    return sorted(out)


def main(argv: list[str]) -> int:
    allow_dirty = "--allow-dirty" in argv
    out_dir = os.path.join(ROOT, "dist")
    if "--out" in argv:
        out_dir = os.path.abspath(argv[argv.index("--out") + 1])
    with open(os.path.join(ROOT, "VERSION"), encoding="ascii") as fh:
        version = fh.read().strip()

    if not allow_dirty and git("status", "--porcelain", "--untracked-files=no").strip():
        return fail("working tree has uncommitted changes; commit first (or --allow-dirty)")

    gen = generated()
    if gen is None:
        return fail("module tree not assembled; run packaging/fetch-upstream.sh")
    missing = [g for g in gen if not os.path.isfile(os.path.join(ROOT, MODULE, g))]
    if missing:
        return fail(f"files of UPSTREAM.sha256 missing: {', '.join(missing[:5])}")

    tracked = [f for f in git("ls-files", "-z", "--", MODULE, *EXTRA).split("\0") if f]
    gen_set = set(gen)
    unknown = []
    for f in (o for o in git("ls-files", "-z", "--others", "--", MODULE).split("\0") if o):
        rel = f[len(MODULE) + 1 :]
        if rel in gen_set or any(fnmatch.fnmatch(os.path.basename(rel), p) or fnmatch.fnmatch(rel, p) for p in ARTIFACTS):
            continue
        unknown.append(f)
    if unknown:
        return fail(f"unexpected files in the module tree: {', '.join(sorted(unknown)[:10])}")

    files = sorted(set(tracked) | {f"{MODULE}/{g}" for g in gen})
    for f in EXTRA:
        if f not in files:
            return fail(f"{f} is not tracked")

    prefix = f"{NAME}-{version}"
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as tar:
        parents = {os.path.dirname(f) for f in files} - {""}
        all_dirs = sorted({"/".join(d.split("/")[: i + 1]) for d in parents for i in range(d.count("/") + 1)})
        for d in ["", *all_dirs]:
            info = tarfile.TarInfo(f"{prefix}/{d}".rstrip("/"))
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.mtime = 0
            tar.addfile(info)
        for f in files:
            path = os.path.join(ROOT, f)
            with open(path, "rb") as fh:
                data = fh.read()
            info = tarfile.TarInfo(f"{prefix}/{f}")
            info.size = len(data)
            info.mode = 0o755 if os.stat(path).st_mode & 0o111 else 0o644
            info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
    os.makedirs(out_dir, exist_ok=True)
    target = os.path.join(out_dir, f"{prefix}.tar")
    with open(target, "wb") as fh:
        fh.write(raw.getvalue())
    digest = hashlib.sha256(raw.getvalue()).hexdigest()
    with open(target + ".sha256", "w", encoding="ascii") as fh:
        fh.write(f"{digest}  {prefix}.tar\n")
    print(f"{digest}  {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
