# Build from a checkout

You need a git checkout (`make dist` builds the tarball from the files Git
tracks; a zip download is not enough), a clean working tree and network access
to git.kernel.org or the GitHub mirror gregkh/linux.

1. Clone the repository:

   ```fish
   git clone https://github.com/Weegee/macbook91-wireless-pub.git
   cd macbook91-wireless-pub
   ```

2. Build the package. `make` fetches the kernel files and checks each against
   `packaging/upstream.lock`. `make arch-pkg` refuses a tree whose tarball is
   not the one the PKGBUILD pins; between releases use `make arch-pkg-dev`:

   ```fish
   make arch-pkg
   ```

3. Install it, then load and check the modules as in steps 4 and 5 of
   [../install.md](../install.md):

   ```fish
   sudo pacman -U dist/macbook91-wireless-dkms-*.pkg.tar.zst
   ```

Checked on 2026-11-09: `git clone` and `make arch-pkg` in a fresh clone (about
one minute). Not checked: the `pacman -U` step.

## Targets

- `make dist` fetches the kernel files at the locked tag and writes `dist/*.tar`.
- `make arch-pkg-dev` builds the package from the working tree.
- `make test` runs the hermetic tests (no hardware, no root); `make` alone lists the targets.

Layout rules: [../../STRUCTURE.md](../../STRUCTURE.md).

## The fetcher

`packaging/fetch-upstream.sh` fetches the files of `packaging/files.list` from
the stable tree on git.kernel.org, checks each against `packaging/upstream.lock`,
applies `patches/` and adds two Kbuild files, once per kernel series. The result
is one self-contained tree `series/<S>/`; the module Makefile builds the one
that matches the target kernel (`UTS_RELEASE`).

- One patch set applies to every series with `patch -F0` (line offsets, no
  fuzz). A new series needs lockfile entries (`--accept-new`) and must take the
  same set; where it does not, rework the set, never split it per series.
- A later stable tag of a shipped series is a lockfile update and changes only
  that series' module ID.
- If git.kernel.org does not answer, the fetcher warns once and takes the rest
  from the mirror. The source never decides what is accepted.
  `--source kernel.org` or `--source github` picks one and turns the fallback off.

The shipped README is installed to `/usr/share/doc/macbook91-wireless-dkms/`;
its links to `docs/` and `diag/` work only on the repository page.
