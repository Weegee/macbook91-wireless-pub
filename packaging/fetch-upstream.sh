#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Assemble the kernel half of src/macbook91-wireless from primary sources.
#
# This repository carries no kernel code. It carries the patches that say what
# this project changes (patches/, one set for every kernel series) and the list
# of kernel files they apply to (packaging/files.list); this script
# reconstructs the rest:
#
#   fetched   every path in files.list, from the stable tree on git.kernel.org,
#             at one tag per kernel series (default: the newest tag of each
#             series in packaging/upstream.lock)
#   derived   series/<S>/kernel/ = the fetched files + patches/*.patch
#             + packaging/overlay/*.Kbuild (the two Kbuild files that build the
#             brcmfmac and hci_uart directories out of tree)
#
# The one patch set must apply to the tag of every series with patch -F0:
# line offsets are tolerated, fuzz is not. A series it does not fit is not
# given a second set; the set is reworked until it fits all of them.
#
# Each series is a self-contained tree, series/<S>/{kernel,patches,
# KERNEL-SERIES,KERNEL-TAG,UPSTREAM.sha256}; the module root holds the list of
# series (KERNEL-SERIES) and the lock lines of their tags (UPSTREAM.lock). The
# manifest of a series names its files relative to series/<S>/, so its hash
# (derived:tree, the source identity of the modules built from it) does not
# depend on which other series the package carries.
#
# It runs at *package* build time (make dist), never at DKMS build time: a
# DKMS rebuild during a kernel upgrade must not depend on the network, and the
# tree staged into /usr/src is complete.
#
# Every fetched file is checked against packaging/upstream.lock before it is
# allowed into the tree, and so is the derived tree as a whole. A known
# (tag, path) pair whose hash changed is a hard failure with no override. A new
# tag is added with --accept-new, and the new lockfile lines are reviewed and
# committed like any other change.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
LOCK="$HERE/upstream.lock"
LIST="$HERE/files.list"
OVERLAY="$HERE/overlay"
CACHE="$ROOT/build/upstream-cache"
DEST="$ROOT/src/macbook91-wireless"

BASE_URL='https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain'

OPT_TAGS=()
OPT_OFFLINE=0
OPT_ACCEPT_NEW=0
OPT_UPDATE_DERIVED=0

die() { printf 'fetch-upstream: ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf 'fetch-upstream: %s\n' "$*" >&2; }

usage() {
	cat <<'USAGE'
usage: fetch-upstream.sh [options]

  --tag vX.Y.Z     assemble this stable tag; repeat for several series. Series
                   not named keep what DEST holds. Default: the newest tag of
                   every series in upstream.lock.
  --dest DIR       assemble into DIR instead of src/macbook91-wireless
  --cache DIR      download cache (default build/upstream-cache)
  --offline        use the cache only; never touch the network
  --accept-new     record hashes for a tag the lockfile does not know yet.
                   Never overrides a hash it already knows.
  --update-derived replace the derived:tree hash of each tag after a change to
                   patches/ or packaging/overlay/ (fetched files stay locked)
  -h, --help       this text
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
	--tag) OPT_TAGS+=("${2:?}"); shift 2 ;;
	--dest) DEST="$(realpath -m "${2:?}")"; shift 2 ;;
	--cache) CACHE="$(realpath -m "${2:?}")"; shift 2 ;;
	--offline) OPT_OFFLINE=1; shift ;;
	--accept-new) OPT_ACCEPT_NEW=1; shift ;;
	--update-derived) OPT_UPDATE_DERIVED=1; shift ;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done

series_of() { # series_of TAG: X.Y of vX.Y[.Z]
	[[ "$1" =~ ^v([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]] || die "not a stable tag: $1"
	printf '%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

TAGS=("${OPT_TAGS[@]}")
if [ "${#TAGS[@]}" -eq 0 ]; then
	# The newest tag of every series the lockfile knows.
	declare -A newest=()
	while IFS= read -r t; do
		newest["$(series_of "$t")"]="$t"
	done < <(awk '$1 ~ /^v[0-9]/ {print $1}' "$LOCK" | sort -uV)
	for s in "${!newest[@]}"; do TAGS+=("${newest[$s]}"); done
	[ "${#TAGS[@]}" -gt 0 ] || die "upstream.lock records no tag; pass --tag"
fi
declare -A SERIES_TAG=()
for t in "${TAGS[@]}"; do
	s="$(series_of "$t")"
	[ -z "${SERIES_TAG[$s]:-}" ] || die "two tags for Linux $s: ${SERIES_TAG[$s]} and $t"
	SERIES_TAG[$s]="$t"
done
PATCHES="$ROOT/patches"
ls "$PATCHES"/*.patch >/dev/null 2>&1 || die "no patches in $PATCHES"

mapfile -t FILES < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$LIST" | grep -v '^$')
[ "${#FILES[@]}" -gt 0 ] || die "files.list is empty"

# The lockfile's hash for (tag, path), or nothing.
locked() { awk -v t="$1" -v p="$2" '$1 == t && $3 == p {print $2}' "$LOCK"; }

NEW=()
check() { # check TAG PATH FILE: the file's bytes against the lockfile
	local want have
	want="$(locked "$1" "$2")"
	have="$(sha256sum "$3" | cut -d' ' -f1)"
	if [ -z "$want" ]; then
		[ "$OPT_ACCEPT_NEW" = 1 ] || die "$1 $2 is not in upstream.lock (review, then --accept-new)"
		NEW+=("$(printf '%-9s  %s  %s' "$1" "$have" "$2")")
	elif [ "$want" != "$have" ]; then
		die "$1 $2: sha256 $have, upstream.lock says $want"
	fi
}

# Assemble in a scratch tree and move it into place only when everything is
# complete.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/macbook91-wireless.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

assemble() { # assemble SERIES TAG: WORK/series/SERIES, from the cache
	local s="$1" tag="$2" f c have p out="$WORK/series/$1" K
	local patches="$PATCHES"
	K="$out/kernel"
	# Fetch into the cache. A cached file is checked like a downloaded one,
	# so the cache cannot bring anything in.
	mkdir -p "$CACHE/$tag"
	for f in "${FILES[@]}"; do
		c="$CACHE/$tag/$f"
		if [ ! -s "$c" ]; then
			[ "$OPT_OFFLINE" = 0 ] || die "$f is not cached for $tag and --offline was given"
			mkdir -p "$(dirname "$c")"
			curl -fsS --retry 3 --retry-delay 2 -o "$c.part" "$BASE_URL/$f?h=$tag" ||
				die "download failed: $f at $tag"
			mv "$c.part" "$c"
		fi
		check "$tag" "$f" "$c"
	done
	for f in "${FILES[@]}"; do
		install -Dm644 "$CACHE/$tag/$f" "$K/$f"
	done
	for p in "$patches"/*.patch; do
		patch -s -p1 -F0 -N --no-backup-if-mismatch -d "$K" -i "$p" ||
			die "$(basename "$p") does not apply cleanly to $tag"
	done
	if find "$K" \( -name '*.orig' -o -name '*.rej' \) | grep . >/dev/null; then
		die "patch left .orig/.rej files"
	fi
	install -Dm644 "$OVERLAY/brcm80211.Kbuild" "$K/drivers/net/wireless/broadcom/brcm80211/Kbuild"
	install -Dm644 "$OVERLAY/bluetooth.Kbuild" "$K/drivers/bluetooth/Kbuild"
	mkdir -p "$out/patches"
	cp "$patches"/*.patch "$out/patches/"
	printf '%s\n' "$s" >"$out/KERNEL-SERIES"
	printf '%s\n' "$tag" >"$out/KERNEL-TAG"
	(cd "$out" && find kernel patches KERNEL-SERIES KERNEL-TAG -type f -print0 | LC_ALL=C sort -z |
		xargs -0 sha256sum) >"$out/UPSTREAM.sha256"

	# The derived tree as a whole: one hash over the series' manifest, so a
	# change in a patch, an overlay or the patch tool shows up as a lockfile
	# difference.
	if [ "$OPT_UPDATE_DERIVED" = 1 ] && [ -n "$(locked "$tag" derived:tree)" ]; then
		have="$(sha256sum "$out/UPSTREAM.sha256" | cut -d' ' -f1)"
		awk -v t="$tag" -v h="$have" '$1 == t && $3 == "derived:tree" {sub($2, h)} {print}' \
			"$LOCK" >"$WORK/lock" && cat "$WORK/lock" >"$LOCK"
		note "derived:tree for $tag is now $have; review the lockfile diff and commit it"
	fi
	check "$tag" derived:tree "$out/UPSTREAM.sha256"
	note "assembled series $s from $tag with $(find "$patches" -name '*.patch' | wc -l) patches"
}

mkdir -p "$WORK/series"
for s in "${!SERIES_TAG[@]}"; do
	assemble "$s" "${SERIES_TAG[$s]}"
done

if [ "${#NEW[@]}" -gt 0 ]; then
	printf '%s\n' "${NEW[@]}" >>"$LOCK"
	note "recorded ${#NEW[@]} new hashes in packaging/upstream.lock; review and commit them"
fi

# Into place: the assembled series replace their directories, other series in
# DEST stay. The layout of earlier versions (one kernel/ at the top) goes.
mkdir -p "$DEST/series"
rm -rf "$DEST/kernel" "$DEST/patches" "$DEST/KERNEL-TAG" "$DEST/UPSTREAM.sha256"
for s in "${!SERIES_TAG[@]}"; do
	rm -rf "${DEST:?}/series/$s"
	mv "$WORK/series/$s" "$DEST/series/$s"
done
# The series list and the lock lines of the tags in DEST, oldest series first.
: >"$DEST/KERNEL-SERIES"
: >"$DEST/UPSTREAM.lock"
for d in "$DEST"/series/*/; do
	[ -r "$d/KERNEL-SERIES" ] || continue
	basename "$d"
done | sort -V | while IFS= read -r s; do
	printf '%s\n' "$s" >>"$DEST/KERNEL-SERIES"
	awk -v t="$(cat "$DEST/series/$s/KERNEL-TAG")" '$1 == t' "$LOCK" >>"$DEST/UPSTREAM.lock"
done
note "assembled $DEST: Linux $(paste -sd' ' "$DEST/KERNEL-SERIES")"
