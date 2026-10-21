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
set -euo pipefail

# --seal <version>: regenerate an existing release directory's SHA256SUMS.
# Promotion writes a STATUS.txt template that has to be filled in by hand, and
# STATUS.txt is itself covered by SHA256SUMS - so the checksums must be redone
# afterwards, by this option rather than by hand.
SEALED=""
if [ "${1:-}" = "--seal" ]; then
	SEALED="${2:?usage: promote-release.sh --seal <version>}"
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# The private gates (maintainer's repository only; absent in a public clone).
PRIV="$ROOT/private"
private_tests() {
	local t
	[ -d "$PRIV/tests" ] || return 0
	for t in "$PRIV"/tests/run-*.sh; do
		[ -e "$t" ] || continue
		echo "private tests: $t"
		bash "$t" || { echo "refusing: $t failed" >&2; return 1; }
	done
}
# Exports a commit built from the working tree (tracked and new files that are not
# ignored; nothing is staged, no ref moves, the index stays as it is) and runs the
# guard over the exported tree. Group P is reported but not counted, as in the exporter.
guard_gate() {
	local tmp tree commit rc=0
	[ -d "$PRIV/export" ] || return 0
	[ -f "$PRIV/export/guard.sh" ] && [ -f "$PRIV/export/export-tree.sh" ] ||
		{ echo "refusing: $PRIV/export lacks guard.sh or export-tree.sh" >&2; return 1; }
	tmp=$(mktemp -d "${TMPDIR:-/tmp}/promote-guard.XXXXXX")
	GIT_INDEX_FILE="$tmp/index" git -C "$ROOT" read-tree HEAD &&
		GIT_INDEX_FILE="$tmp/index" git -C "$ROOT" add -A -- . &&
		tree=$(GIT_INDEX_FILE="$tmp/index" git -C "$ROOT" write-tree) &&
		commit=$(git -C "$ROOT" commit-tree -p HEAD -m "promote gate: working tree" "$tree") ||
		{ echo "refusing: cannot build the commit for the guard" >&2; rm -rf "$tmp"; return 1; }
	if ! bash "$PRIV/export/export-tree.sh" --conf "$PRIV/export" "$ROOT" "$tmp/out" "$commit" >"$tmp/export.log" 2>&1; then
		echo "refusing: the export for the guard failed:" >&2
		tail -n 5 "$tmp/export.log" >&2
		rm -rf "$tmp"
		return 1
	fi
	bash "$PRIV/export/guard.sh" --conf "$PRIV/export" --warn P tree "$tmp/out" >"$tmp/hits.tsv" 2>"$tmp/guard.err" || rc=$?
	if [ "$rc" != 0 ]; then
		echo "refusing: the guard found hits in what would be published (MAC, UUID, IP, SSID, e-mail and serial values are masked, other text such as a host name is shown):" >&2
		head -n 40 "$tmp/hits.tsv" >&2
		tail -n 1 "$tmp/guard.err" >&2
		echo "fix them before committing; --seal <version> runs the guard again" >&2
		rm -rf "$tmp"
		return 1
	fi
	tail -n 1 "$tmp/guard.err"
	rm -rf "$tmp"
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
	[ -n "$src" ] || { echo "no source tarball in $1" >&2; return 1; }
	(cd "$1" && sha256sum -- $TRACKED_FILES "$src" > SHA256SUMS)
	echo "sealed $1/SHA256SUMS over: $TRACKED_FILES $src"
}

if [ -n "$SEALED" ]; then
	DIR="$ROOT/release/$SEALED"
	[ -d "$DIR" ] || { echo "no such release: $DIR" >&2; exit 1; }
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
	echo "refusing: $DEST already exists - release history is not overwritten" >&2
	exit 1
fi

# 2. .SRCINFO must actually match the PKGBUILD being promoted.
GENERATED_SRCINFO="$(cd "$ARCH" && makepkg --printsrcinfo)"
if ! diff -q <(printf '%s\n' "$GENERATED_SRCINFO") "$ARCH/.SRCINFO" >/dev/null 2>&1; then
	echo "refusing: makepkg --printsrcinfo differs from $ARCH/.SRCINFO - run make srcinfo first" >&2
	exit 1
fi

# 3. the built package for this exact version must already exist.
if [ ! -e "$PKGFILE" ]; then
	echo "refusing: $PKGFILE does not exist - build it first (make arch-pkg)" >&2
	exit 1
fi

# 3b. ...from the tarball the PKGBUILD pins, not from some other build.
PINNED=$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" "$ARCH/PKGBUILD")
if [ ! -e "$SRCTAR" ] || [ "$(sha256sum "$SRCTAR" | cut -d' ' -f1)" != "$PINNED" ]; then
	echo "refusing: $SRCTAR is missing or does not match the PKGBUILD's sha256sums - run make arch-pkg" >&2
	exit 1
fi

install -dm755 "$DEST"
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
		echo "pruned release/$v (kept the $keep newest)"
	done < <(printf '%s\n' "${vers[@]}" | sort -V -r)
}
prune_old_releases

guard_gate || { echo "$DEST stays in place for inspection" >&2; exit 1; }
echo "promoted $PKGNAME $PKGVER-$PKGREL to $DEST"
echo "fill in $DEST/STATUS.txt, then re-seal the checksums it is part of:"
echo "  $HERE/promote-release.sh --seal $PKGVER"
