#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build macbook91-wireless-dkms from the working tree: `make arch-pkg-dev`
# (see the root Makefile) assembles the kernel sources, writes the source
# tarball from the tracked files as they are on disk and builds in a fresh
# build/arch. The package lands in dist/.
#
# WIRELESS_FETCH_ARGS passes options to fetch-upstream.sh, e.g. '--offline'
# or '--tag v7.2.10'; without it the fetcher uses the newest tag of every
# series in upstream.lock. Arguments go to makepkg.
#
# A release is built with `make arch-pkg` instead, which also requires a
# committed tree and the tarball checksum pinned in packaging/arch/PKGBUILD.
#
# Text interface (house text HIG, Bash patterns): one "make-package.sh: text"
# line on stderr, then the output of make and makepkg. Usage and exit status:
# make-package.sh --help. The helpers are in lib.sh.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROG=make-package.sh

usage() {
	cat <<USAGE
Usage: $PROG [MAKEPKG_OPTION...]

Build macbook91-wireless-dkms from the working tree into dist/: assemble the
kernel sources, write the source tarball from the tracked files as they are on
disk and build in a fresh build/arch. A release is built with 'make arch-pkg'
instead, which also needs a committed tree and the pinned tarball checksum.

Examples:
  $PROG
  WIRELESS_FETCH_ARGS=--offline $PROG --nocheck

Options:
  MAKEPKG_OPTION   passed to makepkg unchanged
  -h, --help       show this help and exit
  -V, --version    show the version and exit

Environment:
  WIRELESS_FETCH_ARGS   options for fetch-upstream.sh, e.g. '--offline' or
                        '--tag v7.2.10' (default: newest tag of every series
                        in upstream.lock)

Files:
  dist/   the built package and the source tarball

Exit status:
  0  built
  1  failed (make or makepkg report why)

Docs and bug reports: $HOMEPAGE
USAGE
}

. "$ROOT/packaging/lib.sh"
help_or_version "$@"

args=(-C "$ROOT" --no-print-directory arch-pkg-dev "MAKEPKG_FLAGS=$*")
if [ -n "${WIRELESS_FETCH_ARGS:-}" ]; then
	args+=("FETCH_ARGS=$WIRELESS_FETCH_ARGS")
fi
step "building macbook91-wireless-dkms from the working tree (make arch-pkg-dev)"
exec make "${args[@]}"
