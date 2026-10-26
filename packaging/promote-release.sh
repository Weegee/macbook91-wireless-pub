#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# promote-release.sh - copy a built package into release/<pkgver>/ (scheme of
# macbook91-cs4208). It does not commit, tag, push or publish anything.
#
# SHA256SUMS covers exactly the files the repository tracks; the checksum of
# the built package (gitignored, not one of the release files) is recorded in
# STATUS.txt.
#
# --seal <version>: regenerate an existing release directory's SHA256SUMS after
# STATUS.txt, which it covers, has been filled in.
#
# In the maintainer's repository (a top-level private directory with the export
# configuration exists) the private test suites run first and the export guard
# checks, at the end, what the working tree would publish. A clone without that
# directory runs neither.
#
# Text interface (house text HIG, Bash patterns): what the script does is
# "promote-release.sh: text" lines on stderr, failures "promote-release.sh:
# error: text" with indented hints, exit status 0 / 1 / 2. It has no result on
# stdout; the output of the private test suites passes through. Usage and exit
# status: promote-release.sh --help. The helpers are in lib.sh.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PROG=promote-release.sh

usage() {
	cat <<USAGE
Usage: $PROG [--seal VERSION]

Copy the built package into release/VERSION/ (scheme of macbook91-cs4208). It
does not commit, tag, push or publish anything. In the maintainer's repository
the private tests run first and the export guard checks, at the end, what the
working tree would publish.

Examples:
  $PROG
  $PROG --seal 20261026.02

Options:
  --seal VERSION   regenerate SHA256SUMS of release/VERSION after STATUS.txt,
                   which it covers, has been filled in
  -h, --help       show this help and exit
  -V, --version    show the version and exit

Environment:
  TMPDIR   where the export for the guard is built (default /tmp)

Files:
  packaging/arch/   PKGBUILD, .SRCINFO and the install file it copies
  dist/             the built package and source tarball it takes
  release/VERSION/  the result; history, never overwritten (the 2 newest stay)

Exit status:
  0  done
  1  refused or failed: a check or a gate did not pass
  2  invalid usage

Docs and bug reports: $HOMEPAGE
USAGE
}

. "$HERE/lib.sh"
help_or_version "$@"

# --seal <version>: regenerate an existing release directory's SHA256SUMS.
# Promotion writes a STATUS.txt template that has to be filled in by hand, and
# STATUS.txt is itself covered by SHA256SUMS - so the checksums must be redone
# afterwards, by this option rather than by hand.
SEALED=""
while [ $# -gt 0 ]; do
	case "$1" in
	--seal) need_value "$1" "$#"; SEALED=$2; shift 2 ;;
	--) shift; [ $# -eq 0 ] || usage_error "unexpected argument: $1"; break ;;
	-*) usage_error "unknown option: $1" ;;
	*) usage_error "unexpected argument: $1" ;;
	esac
done
if [ -n "$SEALED" ] && [ ! -d "$ROOT/release/$SEALED" ]; then
	die "no such release: release/$SEALED" "Releases there: $(cd "$ROOT/release" && printf '%s ' */ | sed 's|/||g; s/ $//')"
fi

# What an interrupted or failed run leaves behind is removed: the scratch tree
# of the guard, and a release directory that this run began and did not finish.
GUARD_TMP=''
PROMOTING=''
cleanup() {
	[ -z "$GUARD_TMP" ] || rm -rf "$GUARD_TMP"
	[ -z "$PROMOTING" ] || rm -rf "$PROMOTING"
}
trap cleanup EXIT
trap_signals

# The private gates (maintainer's repository only; absent in a public clone).
PRIV="$ROOT/private"
private_tests() {
	local t
	[ -d "$PRIV/tests" ] || return 0
	for t in "$PRIV"/tests/run-*.sh; do
		[ -e "$t" ] || continue
		step "running private tests: $t"
		bash "$t" || { err "private tests failed: $t" "Fix them, then run $PROG again"; return 1; }
	done
}
# Exports a commit built from the working tree (tracked and new files that are not
# ignored; nothing is staged, no ref moves, the index stays as it is) and runs the
# guard over the exported tree. Group P is reported but not counted, as in the exporter.
guard_gate() {
	local tree commit rc=0
	[ -d "$PRIV/export" ] || return 0
	[ -f "$PRIV/export/guard.sh" ] && [ -f "$PRIV/export/export-tree.sh" ] ||
		{ err "$PRIV/export lacks guard.sh or export-tree.sh"; return 1; }
	step "running the export guard over the working tree"
	GUARD_TMP=$(mktemp -d "${TMPDIR:-/tmp}/promote-guard.XXXXXX")
	GIT_INDEX_FILE="$GUARD_TMP/index" git -C "$ROOT" read-tree HEAD &&
		GIT_INDEX_FILE="$GUARD_TMP/index" git -C "$ROOT" add -A -- . &&
		tree=$(GIT_INDEX_FILE="$GUARD_TMP/index" git -C "$ROOT" write-tree) &&
		commit=$(git -C "$ROOT" commit-tree -p HEAD -m "promote gate: working tree" "$tree") ||
		{ err "cannot build the commit for the guard"; return 1; }
	if ! bash "$PRIV/export/export-tree.sh" --conf "$PRIV/export" "$ROOT" "$GUARD_TMP/out" "$commit" >"$GUARD_TMP/export.log" 2>&1; then
		err "the export for the guard failed, last lines of its log:"
		tail -n 5 "$GUARD_TMP/export.log" | sed 's/^/  /' >&2
		return 1
	fi
	bash "$PRIV/export/guard.sh" --conf "$PRIV/export" --warn P tree "$GUARD_TMP/out" >"$GUARD_TMP/hits.tsv" 2>"$GUARD_TMP/guard.err" || rc=$?
	if [ "$rc" != 0 ]; then
		err "the guard found hits in what would be published" \
			"MAC, UUID, IP, SSID, e-mail and serial values are masked, other text such as a host name is shown:"
		head -n 40 "$GUARD_TMP/hits.tsv" | sed 's/^/  /' >&2
		tail -n 1 "$GUARD_TMP/guard.err" | sed 's/^/  /' >&2
		printf '  Fix them before committing; %s --seal VERSION runs the guard again\n' "$PROG" >&2
		return 1
	fi
	step "export $(tail -n 1 "$GUARD_TMP/guard.err")"
}
private_tests

# The files a clone has, and therefore the ones SHA256SUMS may name. The
# lockfile says which kernel bytes the release was assembled from.
TRACKED_FILES='PKGBUILD .SRCINFO macbook91-wireless.install upstream.lock STATUS.txt'
seal() { # seal DIR
	local src="" f
	for f in "$1"/*.tar; do
		[ -e "$f" ] && { src=$(basename "$f"); break; }
	done
	[ -n "$src" ] || { err "no source tarball in $1" "Promote a built package first: $PROG"; return 1; }
	(cd "$1" && sha256sum -- $TRACKED_FILES "$src" > SHA256SUMS)
	step "sealed $1/SHA256SUMS over: $TRACKED_FILES $src"
}

if [ -n "$SEALED" ]; then
	DIR="$ROOT/release/$SEALED"
	seal "$DIR"
	guard_gate
	exit 0
fi

ARCH="$HERE/arch"
PKGVER=$(sed -n 's/^pkgver=//p' "$ARCH/PKGBUILD" | head -1)
PKGREL=$(sed -n 's/^pkgrel=//p' "$ARCH/PKGBUILD" | head -1)
PKGNAME=$(sed -n 's/^pkgname=//p' "$ARCH/PKGBUILD" | head -1)

DEST="$ROOT/release/$PKGVER"
PKGFILE="$ROOT/dist/${PKGNAME}-${PKGVER}-${PKGREL}-x86_64.pkg.tar.zst"
SRCTAR="$ROOT/dist/${PKGNAME}-${PKGVER}.tar"

# 1. release/<ver>/ is promoted, immutable history - never overwritten.
if [ -e "$DEST" ]; then
	die "release/$PKGVER already exists" \
		"Release history is not overwritten. Raise pkgver in packaging/arch/PKGBUILD for a new release," \
		"or regenerate its checksums: $PROG --seal $PKGVER"
fi

# 2. .SRCINFO must actually match the PKGBUILD being promoted.
GENERATED_SRCINFO="$(cd "$ARCH" && makepkg --printsrcinfo)"
if ! diff -q <(printf '%s\n' "$GENERATED_SRCINFO") "$ARCH/.SRCINFO" >/dev/null 2>&1; then
	die "makepkg --printsrcinfo differs from $ARCH/.SRCINFO" "Run: make srcinfo"
fi

# 3. the built package for this exact version must already exist.
if [ ! -e "$PKGFILE" ]; then
	die "$PKGFILE does not exist" "Build it first: make arch-pkg"
fi

# 3b. ...from the tarball the PKGBUILD pins, not from some other build.
PINNED=$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" "$ARCH/PKGBUILD")
if [ ! -e "$SRCTAR" ] || [ "$(sha256sum "$SRCTAR" | cut -d' ' -f1)" != "$PINNED" ]; then
	die "$SRCTAR is missing or does not match the sha256sums of the PKGBUILD" "Run: make arch-pkg"
fi

install -dm755 "$DEST"
PROMOTING="$DEST"
cp "$ARCH/PKGBUILD" "$DEST/PKGBUILD"
cp "$ARCH/.SRCINFO" "$DEST/.SRCINFO"
cp "$ARCH/macbook91-wireless.install" "$DEST/macbook91-wireless.install"
cp "$SRCTAR" "$DEST/$(basename "$SRCTAR")"
cp "$HERE/upstream.lock" "$DEST/upstream.lock"
cp "$PKGFILE" "$DEST/$(basename "$PKGFILE")"

PKGSUM=$(sha256sum "$PKGFILE" | cut -d' ' -f1)

cat > "$DEST/STATUS.txt" <<EOF
$PKGNAME $PKGVER-$PKGREL - TODO: WITHDRAWN / CANDIDATE / etc.

TODO: fill in before this release is considered documented. See prior
release/*/STATUS.txt for the level of detail expected: what changed, why,
what was measured, what is not yet verified, and the test suite counts.

Built package (not tracked and not one of the release files; makepkg output differs per machine):
$PKGSUM  $(basename "$PKGFILE")
EOF

seal "$DEST"
PROMOTING=''

# 4. retention (STRUCTURE.md, release/): only the two newest release
# directories are kept. Older ones are removed only after the new one is fully
# written and sealed, and every removal is named. A removed directory is no
# longer part of this repository.
prune_old_releases() {
	local keep=2 n=0 v
	local vers=()
	for v in "$ROOT"/release/*/; do
		[ -d "$v" ] || continue
		vers+=("$(basename "$v")")
	done
	[ "${#vers[@]}" -gt 0 ] || return 0
	while read -r v; do
		[ -n "$v" ] || continue
		n=$((n + 1))
		if [ "$n" -le "$keep" ]; then
			continue
		fi
		rm -rf "${ROOT:?}/release/$v"
		step "pruned release/$v (kept the $keep newest)"
	done < <(printf '%s\n' "${vers[@]}" | sort -V -r)
}
prune_old_releases

guard_gate || { note "release/$PKGVER stays in place for inspection"; exit 1; }
step "promoted $PKGNAME $PKGVER-$PKGREL to release/$PKGVER"
note "fill in release/$PKGVER/STATUS.txt, then re-seal the checksums it is part of:" \
	"$HERE/promote-release.sh --seal $PKGVER"
