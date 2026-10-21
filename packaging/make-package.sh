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
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
args=(-C "$ROOT" --no-print-directory arch-pkg-dev "MAKEPKG_FLAGS=$*")
if [ -n "${WIRELESS_FETCH_ARGS:-}" ]; then
	args+=("FETCH_ARGS=$WIRELESS_FETCH_ARGS")
fi
exec make "${args[@]}"
