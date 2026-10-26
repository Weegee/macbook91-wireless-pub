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
# Text interface (house text HIG, Bash patterns): progress and results are
# "fetch-upstream.sh: text" lines on stderr, failures "fetch-upstream.sh:
# error: text" with indented hints, exit status 0 / 1 / 2. Usage, options and
# exit status: fetch-upstream.sh --help. The helpers are in lib.sh.
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

PROG=fetch-upstream.sh
OPT_TAGS=()
OPT_OFFLINE=0
OPT_ACCEPT_NEW=0
OPT_UPDATE_DERIVED=0
OPT_TIMEOUT=120

usage() {
	cat <<USAGE
Usage: $PROG [OPTIONS]

Assemble the kernel half of src/macbook91-wireless from the stable tree on
git.kernel.org, locked by packaging/upstream.lock. It runs at package build
time (make dist), never at DKMS build time.

Examples:
  $PROG
  $PROG --tag v7.3 --offline
  $PROG --update-derived

Options:
  --tag vX.Y.Z        assemble this stable tag; repeat for several series.
                      Series not named keep what DEST holds. Default: the
                      newest tag of every series in upstream.lock
  --dest DIR          assemble into DIR (default src/macbook91-wireless)
  --cache DIR         download cache (default build/upstream-cache)
  --offline           use the cache only; never touch the network
  --timeout SECONDS   give up on one download after SECONDS (default 120)
  --accept-new        record hashes for a tag the lockfile does not know yet;
                      never overrides a hash it already knows
  --update-derived    replace the derived:tree hash of each tag after a change
                      to patches/ or packaging/overlay/ (fetched files stay
                      locked)
  -h, --help          show this help and exit
  -V, --version       show the version and exit

Environment:
  TMPDIR   where the scratch tree is built (default /tmp)

Files:
  packaging/upstream.lock   hashes of every fetched file and derived tree
  packaging/files.list      the kernel files that are fetched
  build/upstream-cache/     downloaded files, checked like fresh ones

Exit status:
  0  assembled
  1  failed: download, hash mismatch, a patch that does not apply
  2  invalid usage

Docs and bug reports: $HOMEPAGE
USAGE
}

. "$HERE/lib.sh"
help_or_version "$@"

while [ $# -gt 0 ]; do
	case "$1" in
	--tag)
		need_value "$1" "$#"
		[[ $2 =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
			usage_error "not a stable tag: $2" "Use a tag like v6.18.55 or v7.3"
		OPT_TAGS+=("$2"); shift 2 ;;
	--dest) need_value "$1" "$#"; DEST="$(realpath -m "$2")"; shift 2 ;;
	--cache) need_value "$1" "$#"; CACHE="$(realpath -m "$2")"; shift 2 ;;
	--timeout)
		need_value "$1" "$#"; need_number "$1" "$2"
		[ "$2" -gt 0 ] || usage_error "--timeout must be at least 1 second"
		OPT_TIMEOUT=$2; shift 2 ;;
	--offline) OPT_OFFLINE=1; shift ;;
	--accept-new) OPT_ACCEPT_NEW=1; shift ;;
	--update-derived) OPT_UPDATE_DERIVED=1; shift ;;
	--) shift; [ $# -eq 0 ] || usage_error "unexpected argument: $1"; break ;;
	-*) usage_error "unknown option: $1" ;;
	*) usage_error "unexpected argument: $1" ;;
	esac
done

series_of() { # series_of TAG: X.Y of vX.Y[.Z]
	[[ "$1" =~ ^v([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]] ||
		die "upstream.lock holds a tag that is not a stable tag: $1" "Fix packaging/upstream.lock"
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
	[ "${#TAGS[@]}" -gt 0 ] || die "upstream.lock records no tag" "Pass one with --tag"
fi
declare -A SERIES_TAG=()
for t in "${TAGS[@]}"; do
	s="$(series_of "$t")"
	[ -z "${SERIES_TAG[$s]:-}" ] ||
		usage_error "two tags for Linux $s: ${SERIES_TAG[$s]} and $t" "Name one tag per series"
	SERIES_TAG[$s]="$t"
done
PATCHES="$ROOT/patches"
ls "$PATCHES"/*.patch >/dev/null 2>&1 || die "no patches in $PATCHES"

mapfile -t FILES < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$LIST" | grep -v '^$')
[ "${#FILES[@]}" -gt 0 ] || die "files.list is empty"

# Downloads still missing, counted first: a cold cache announces its size, and
# --offline fails before anything is assembled (EIN-6, FOR-4).
MISSING=0
FIRST_MISSING=''
for t in "${SERIES_TAG[@]}"; do
	for f in "${FILES[@]}"; do
		[ -s "$CACHE/$t/$f" ] && continue
		MISSING=$((MISSING + 1))
		[ -n "$FIRST_MISSING" ] || FIRST_MISSING="$f is not cached for $t"
	done
done
DOWNLOADED=0
if [ "$MISSING" -gt 0 ]; then
	[ "$OPT_OFFLINE" = 0 ] ||
		die "$FIRST_MISSING and --offline was given" \
			"Missing in total: $(plural "$MISSING" file files)" \
			"Run without --offline to download them"
	step "downloading $(plural "$MISSING" file files) from git.kernel.org (Ctrl+C cancels)"
fi

# The lockfile's hash for (tag, path), or nothing.
locked() { awk -v t="$1" -v p="$2" '$1 == t && $3 == p {print $2}' "$LOCK"; }

NEW=()
check() { # check TAG PATH FILE: the file's bytes against the lockfile
	local want have
	want="$(locked "$1" "$2")"
	have="$(sha256sum "$3" | cut -d' ' -f1)"
	if [ -z "$want" ]; then
		[ "$OPT_ACCEPT_NEW" = 1 ] ||
			die "$1 $2 is not in upstream.lock" "Review the tag, then run again with --accept-new"
		NEW+=("$(printf '%-9s  %s  %s' "$1" "$have" "$2")")
	elif [ "$want" != "$have" ]; then
		die "$1 $2 does not match upstream.lock" "sha256 is $have" "upstream.lock says $want"
	fi
}

# Assemble in a scratch tree and move it into place only when everything is
# complete.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/macbook91-wireless.XXXXXX")"
PART=''
cleanup() { rm -rf "$WORK"; [ -z "$PART" ] || rm -f "$PART"; }
trap cleanup EXIT
trap_signals

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
			PART="$c.part"
			curl -fsS --retry 3 --retry-delay 2 --connect-timeout 20 --max-time "$OPT_TIMEOUT" \
				-o "$PART" "$BASE_URL/$f?h=$tag" ||
				die "download failed: $f at $tag" \
					"Check the network and run again; the files downloaded so far stay in $CACHE"
			mv "$PART" "$c"
			PART=''
			DOWNLOADED=$((DOWNLOADED + 1))
			if [ $((DOWNLOADED % 25)) -eq 0 ] && [ "$DOWNLOADED" -lt "$MISSING" ]; then
				step "downloaded $DOWNLOADED of $MISSING files"
			fi
		fi
		check "$tag" "$f" "$c"
	done
	for f in "${FILES[@]}"; do
		install -Dm644 "$CACHE/$tag/$f" "$K/$f"
	done
	for p in "$patches"/*.patch; do
		patch -s -p1 -F0 -N --no-backup-if-mismatch -d "$K" -i "$p" ||
			die "$(basename "$p") does not apply cleanly to $tag" \
				"The patch set must apply to the tag of every series with patch -F0"
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
		note "derived:tree for $tag is now $have" \
			"Review and commit it: git diff packaging/upstream.lock"
	fi
	check "$tag" derived:tree "$out/UPSTREAM.sha256"
	step "assembled series $s from $tag with $(plural "$(find "$patches" -name '*.patch' | wc -l)" patch patches)"
}

mkdir -p "$WORK/series"
for s in "${!SERIES_TAG[@]}"; do
	assemble "$s" "${SERIES_TAG[$s]}"
done

if [ "${#NEW[@]}" -gt 0 ]; then
	printf '%s\n' "${NEW[@]}" >>"$LOCK"
	note "recorded $(plural "${#NEW[@]}" hash hashes) in packaging/upstream.lock" \
		"Review and commit them: git diff packaging/upstream.lock"
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
[ "$DOWNLOADED" -eq 0 ] || step "downloaded $(plural "$DOWNLOADED" file files)"
step "assembled $DEST: Linux $(paste -sd' ' "$DEST/KERNEL-SERIES")"
