#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Hermetic checks of the repository: no hardware, no root, no network (the
# fetcher runs --offline against build/upstream-cache and is skipped without
# it). Exit status 1 on any failure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/macbook91-wireless-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok() { printf 'ok    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
skip() { printf 'skip  %s\n' "$*"; }
cd "$ROOT" || exit 1

# The checks cover the files of the public tree. A top-level directory named
# "private", if one exists, is not part of it.
tracked() { git ls-files -z "$@" ':!private'; }

# 1. Nothing proprietary, binary or private is tracked ------------------------
if tracked | xargs -0 -r ls -d 2>/dev/null |
	grep -Ei '\.(bin|hcd|ko|zst|xz|dmg|pkg|kext|img|snoop|btsnoop|pcap|clmb|txcap|pyc)$|(^|/)[.]context/' >/dev/null; then
	bad "a firmware, binary, capture or local-only file is tracked"
else
	ok "no firmware, binaries, captures or local-only files tracked"
fi
# Release source tarballs (release/<version>/*.tar) are the exception; their
# members are checked like tracked files instead.
big=$(tracked | xargs -0 -r stat -c '%s %n' 2>/dev/null | awk '$1 > 1048576 {print $2}' | grep -vE '^release/[^/]+/[^/]+\.tar$')
[ -z "$big" ] && ok "no tracked file over 1 MiB" || bad "tracked files over 1 MiB: $big"
for t in $(tracked -- 'release/*.tar' | tr '\0' ' '); do
	if tar -tf "$t" | grep -Ei '\.(bin|hcd|ko|zst|xz|dmg|pkg|kext|img|snoop|pcap)$|/[.]context/' >/dev/null; then
		bad "$t holds a binary or private file"
	else
		ok "$t holds sources only"
	fi
done
if tracked | xargs -0 -r grep -IlE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' 2>/dev/null | grep -v '^tests/run-tests.sh$' | grep . >/dev/null; then
	bad "a MAC/Bluetooth address in: $(tracked | xargs -0 -r grep -IlE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | grep -v '^tests/run-tests.sh$' | tr '\n' ' ')"
else
	ok "no MAC or Bluetooth addresses tracked"
fi
if tracked | xargs -0 -r grep -IlE '\b(192\.168|10\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+\b|\b2[0-9a-f]{3}:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}::' 2>/dev/null | grep -v '^tests/run-tests.sh$' | grep . >/dev/null; then
	bad "an IP address in: $(tracked | xargs -0 -r grep -IlE '\b(192\.168|10\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+\b|\b2[0-9a-f]{3}:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}::' | grep -v '^tests/run-tests.sh$' | tr '\n' ' ')"
else
	ok "no private IPv4 or global IPv6 addresses tracked"
fi
# Patches quote kernel code, whose authors' addresses are public; their own
# From: lines are checked. grep runs per file: fed one concatenated stream,
# -I would give up at the first binary data (release/*.tar) and check
# nothing after it.
mail_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
mails=$({ tracked -- . ':!patches' | xargs -0 -r grep -IhoE "$mail_re"; grep -h '^From: ' patches/*/*.patch | grep -oE "$mail_re"; } 2>/dev/null |
	grep -vE '(noreply|no-reply)[.@]|@users\.noreply\.github\.com$|@localhos[t]$|@example\.(com|org)$' | sort -u)
[ -z "$mails" ] && ok "no personal e-mail addresses tracked" || bad "e-mail addresses tracked: $mails"
if tracked -- 'src/macbook91-wireless/series' 'src/macbook91-wireless/kernel' 'src/macbook91-wireless/patches' | grep . >/dev/null; then
	bad "assembled kernel sources are tracked"
else
	ok "assembled kernel sources are not tracked"
fi

# 2. Scripts --------------------------------------------------------------------
for f in packaging/fetch-upstream.sh packaging/promote-release.sh packaging/make-package.sh tools/macbook91-wireless-verify tools/dev-*.sh tests/run-tests.sh; do
	bash -n "$f" || bad "syntax: $f"
done
if command -v shellcheck >/dev/null; then
	shellcheck -S warning packaging/fetch-upstream.sh packaging/promote-release.sh packaging/make-package.sh tools/macbook91-wireless-verify tools/dev-*.sh &&
		ok "shellcheck" || bad "shellcheck"
else
	skip "shellcheck not installed"
fi
# With pipefail, a grep -q that exits at the first match kills its writer with
# SIGPIPE and the pipeline reports failure: a found match reads as none.
pq=$(awk 'FNR == 1 {prev = ""} {
	if ($0 ~ /\|[[:space:]]*grep -[A-Za-z]*q/ || (prev ~ /\|[[:space:]]*$/ && $0 ~ /^[[:space:]]*grep -[A-Za-z]*q/))
		print FILENAME ":" FNR
	prev = $0 }' packaging/fetch-upstream.sh packaging/promote-release.sh packaging/make-package.sh tools/macbook91-wireless-verify tools/dev-*.sh tests/run-tests.sh)
[ -z "$pq" ] && ok "no grep -q at the end of a pipeline" || bad "grep -q ends a pipeline (pipefail): $pq"
python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' packaging/mkdist.py 2>/dev/null &&
	ok "mkdist.py parses" || bad "mkdist.py"

# 3. Patches and lockfile -------------------------------------------------------
if grep -l 'TEST ONLY\|macbook91_halt_fw' patches/*/*.patch 2>/dev/null | grep . >/dev/null; then
	bad "a test-only patch is in patches/"
else
	ok "no test-only patches"
fi
mapfile -t files < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' packaging/files.list | grep -v '^$')
declare -A newest=()
for tag in $(awk '$1 ~ /^v[0-9]/ {print $1}' packaging/upstream.lock | sort -uV); do
	missing=0
	for f in "${files[@]}" derived:tree; do
		awk -v t="$tag" -v p="$f" '$1 == t && $3 == p {found=1} END {exit !found}' packaging/upstream.lock || missing=$((missing + 1))
	done
	[ "$missing" = 0 ] && ok "upstream.lock covers files.list for $tag" || bad "upstream.lock: $missing entries missing for $tag"
	series=$(sed -E 's/^v([0-9]+\.[0-9]+).*/\1/' <<<"$tag")
	if [ -d "patches/$series" ] && ls "patches/$series"/*.patch >/dev/null 2>&1; then
		ok "patches/$series exists for $tag"
	else
		bad "no patches/$series for $tag"
	fi
	newest[$series]=$tag
done
# Every patch series has a lock tag and the other way round.
sers_lock=$(printf '%s\n' "${!newest[@]}" | sort -V | paste -sd' ')
sers_patches=$(for d in patches/*/; do basename "$d"; done | sort -V | paste -sd' ')
[ "$sers_lock" = "$sers_patches" ] && ok "lock series ($sers_lock) equal patches/ series" ||
	bad "lock series '$sers_lock', patches/ series '$sers_patches'"
# The module's dkms.conf: BUILD_EXCLUSIVE_KERNEL is generated at install time
# from the series list, every module is taken from the flat build/ directory.
grep -Fqx 'BUILD_EXCLUSIVE_KERNEL="^@SERIES_RE@\."' src/macbook91-wireless/dkms.conf &&
	[ "$(grep -c '^BUILT_MODULE_LOCATION\[[0-4]\]="build/"$' src/macbook91-wireless/dkms.conf)" = 5 ] &&
	ok "dkms.conf: series pattern placeholder, 5 modules from build/" || bad "dkms.conf template"
# The module Makefile builds the kernel's own series, and skips a series it does
# not carry with status 0 and no build (fake kernel headers, no compiler run).
mkdir -p "$TMP/skip/kdir/include/generated" "$TMP/skip/tree"
cp src/macbook91-wireless/Makefile "$TMP/skip/tree/"
printf '6.18\n7.2\n' >"$TMP/skip/tree/KERNEL-SERIES"
for rel in 6.12.1-test 7.3.0-test 6.180.1-test; do
	printf '#define UTS_RELEASE "%s"\n' "$rel" >"$TMP/skip/kdir/include/generated/utsrelease.h"
	if out=$(make -s -C "$TMP/skip/tree" KDIR="$TMP/skip/kdir" 2>&1) && grep -F 'Nothing built' <<<"$out" >/dev/null &&
		[ ! -e "$TMP/skip/tree/build" ] && make -s -C "$TMP/skip/tree" KDIR="$TMP/skip/kdir" clean >/dev/null 2>&1; then
		ok "Makefile skips Linux ${rel%%-*} (not a shipped series)"
	else
		bad "Makefile did not skip Linux ${rel%%-*}: $out"
	fi
done
printf '#define UTS_RELEASE "7.2.11-test"\n' >"$TMP/skip/kdir/include/generated/utsrelease.h"
if make -s -C "$TMP/skip/tree" KDIR="$TMP/skip/kdir" >"$TMP/skip/out" 2>&1; then
	bad "Makefile built Linux 7.2 without an assembled series/7.2"
else
	grep -F 'series/7.2 is not assembled' "$TMP/skip/out" >/dev/null && ok "Makefile refuses a listed series that is not assembled" ||
		bad "Makefile: $(tail -n1 "$TMP/skip/out")"
fi

# 4. Offline reassembly of every series reproduces the lockfile's derived tree -
# Each series alone, then all of them as make dist does.
cache_ok=1
args=()
for series in "${!newest[@]}"; do
	tag=${newest[$series]}
	if [ -d "build/upstream-cache/$tag" ]; then
		cp packaging/upstream.lock "$TMP/lock.before"
		if packaging/fetch-upstream.sh --offline --tag "$tag" --dest "$TMP/tree-$series" 2>"$TMP/fetch.log"; then
			want=$(awk -v t="$tag" '$1 == t && $3 == "derived:tree" {print $2}' packaging/upstream.lock)
			have=$(sha256sum "$TMP/tree-$series/series/$series/UPSTREAM.sha256" | cut -d' ' -f1)
			[ "$want" = "$have" ] && [ "$(cat "$TMP/tree-$series/series/$series/KERNEL-TAG")" = "$tag" ] &&
				[ "$(cat "$TMP/tree-$series/KERNEL-SERIES")" = "$series" ] &&
				(cd "$TMP/tree-$series/series/$series" && sha256sum --quiet -c UPSTREAM.sha256) &&
				ok "offline reassembly of Linux $series from $tag matches upstream.lock" ||
				bad "reassembled Linux $series: manifest $have, upstream.lock says $want"
		else
			bad "offline reassembly of $tag: $(tail -n1 "$TMP/fetch.log")"
		fi
		cmp -s packaging/upstream.lock "$TMP/lock.before" || bad "the fetcher changed upstream.lock without --accept-new"
		args+=(--tag "$tag")
	else
		cache_ok=0
		skip "no cache for $tag (build/upstream-cache); run packaging/fetch-upstream.sh"
	fi
done
if [ "$cache_ok" = 1 ]; then
	if packaging/fetch-upstream.sh --offline --dest "$TMP/tree" 2>"$TMP/fetch.log" &&
		[ "$(paste -sd' ' "$TMP/tree/KERNEL-SERIES")" = "$sers_lock" ] &&
		[ "$(awk '$1 ~ /^v[0-9]/ {print $1}' "$TMP/tree/UPSTREAM.lock" | sort -u | wc -l)" = "${#newest[@]}" ]; then
		ok "offline reassembly of all series ($sers_lock) at once"
	else
		bad "offline reassembly of all series: $(tail -n1 "$TMP/fetch.log")"
	fi
	# A later tag of one series must not touch the trees of the others.
	if [ -d "$TMP/tree-7.2/series/7.2" ]; then
		cmp -s "$TMP/tree-7.2/series/7.2/UPSTREAM.sha256" "$TMP/tree/series/7.2/UPSTREAM.sha256" &&
			ok "the manifest of series 7.2 does not depend on the other series" || bad "series 7.2 manifest differs"
	fi
fi
# The 7.2 source identity (the module ID <version>+494451d9a8ce5f25 and the
# derived:tree of v7.2.9) is pinned: the series layout must not change it. A
# deliberate change of patches/7.2, the overlays or the v7.2 tag changes this
# value and is recorded here together with the lockfile.
if [ -r "$TMP/tree-7.2/series/7.2/UPSTREAM.sha256" ]; then
	id72=$(sha256sum "$TMP/tree-7.2/series/7.2/UPSTREAM.sha256" | cut -c1-16)
	[ "$id72" = 494451d9a8ce5f25 ] && ok "source ID of series 7.2 is 494451d9a8ce5f25" || bad "source ID of series 7.2 is $id72, pinned 494451d9a8ce5f25"
else
	skip "source ID of series 7.2: not reassembled"
fi

# 5. LE advertising fixup, compiled from the assembled hci_bcm.c --------------
n=0
for tree in "$TMP"/tree-*; do
	[ -d "$tree" ] || continue
	src="$(echo "$tree"/series/*/kernel/drivers/bluetooth/hci_bcm.c)"
	[ -r "$src" ] && command -v cc >/dev/null || continue
	n=$((n + 1))
	sdir=${tree##*/tree-}
	awk '/^static void bcm_fixup_le_adv_report\(/,/^}/' "$src" >"$TMP/le_adv_fixup.inc"
	if [ -s "$TMP/le_adv_fixup.inc" ] &&
		cc -std=gnu11 -Wall -Werror -g -fsanitize=address,undefined -fno-sanitize-recover=all \
			-I"$TMP" -o "$TMP/le" tests/test_le_adv_fixup.c 2>"$TMP/cc.log" &&
		"$TMP/le" >/dev/null 2>"$TMP/le.log"; then
		ok "LE advertising type fixup, Linux $sdir (host test, ASan/UBSan)"
	else
		bad "LE advertising type fixup, Linux $sdir: $(cat "$TMP/cc.log" "$TMP/le.log" 2>/dev/null | head -n3)"
	fi
done
[ "$n" -gt 0 ] || skip "LE advertising fixup test: no assembled hci_bcm.c or no compiler"

# 6. Install layout and reproducible tarball ----------------------------------
if [ -r src/macbook91-wireless/KERNEL-SERIES ]; then
	mapfile -t sers <src/macbook91-wireless/KERNEL-SERIES
	if make -s install DESTDIR="$TMP/root" PREFIX=/usr >"$TMP/install.log" 2>&1; then
		v=$(cat VERSION)
		d="$TMP/root/usr/src/macbook91-wireless-$v"
		# dkms.conf: version and the pattern generated from the series list.
		re=$(printf '%s\n' "${sers[@]}" | sed 's/\./\\./g' | paste -sd'|')
		grep -qx "PACKAGE_VERSION=\"$v\"" "$d/dkms.conf" &&
			grep -Fqx "BUILD_EXCLUSIVE_KERNEL=\"^($re)\\.\"" "$d/dkms.conf" &&
			! grep -q '@' "$d/dkms.conf" && ok "dkms.conf placeholders filled" ||
			bad "dkms.conf: $(grep -E 'PACKAGE_VERSION|BUILD_EXCLUSIVE' "$d/dkms.conf" | tr '\n' ' ')"
		# The installed pattern, as DKMS evaluates it (bash =~), against the
		# series list: every series matches, near misses do not.
		pat=$(sed -n 's/^BUILD_EXCLUSIVE_KERNEL="\(.*\)"$/\1/p' "$d/dkms.conf")
		pm=""
		for s in "${sers[@]}"; do
			[[ "$s.1-1-test" =~ $pat ]] && [[ "$s.0" =~ $pat ]] || pm+=" accepts-not:$s"
			[[ "${s}0.1-test" =~ $pat ]] && pm+=" accepts:${s}0"
			[[ "x$s.1-test" =~ $pat ]] && pm+=" accepts:x$s"
		done
		for k in 6.12.1-1-lts 7.3.0-1-test 5.15.0 6.1.0 17.2.1; do
			kser=$(sed -E 's/^([0-9]+\.[0-9]+).*/\1/' <<<"$k")
			listed=0
			for s in "${sers[@]}"; do [ "$s" = "$kser" ] && listed=1; done
			if [[ "$k" =~ $pat ]]; then
				[ "$listed" = 1 ] || pm+=" accepts:$k"
			else
				[ "$listed" = 0 ] || pm+=" rejects:$k"
			fi
		done
		[ -z "$pm" ] && ok "BUILD_EXCLUSIVE_KERNEL matches exactly the series list (${sers[*]})" || bad "BUILD_EXCLUSIVE_KERNEL:$pm"
		# The series list is the list of patch series and of series trees.
		have=$(for x in "$d"/series/*/; do basename "$x"; done | sort -V | paste -sd' ')
		[ "$have" = "${sers[*]}" ] && [ "${sers[*]}" = "$sers_patches" ] &&
			ok "installed series trees ($have) equal KERNEL-SERIES and patches/" ||
			bad "series: trees '$have', KERNEL-SERIES '${sers[*]}', patches '$sers_patches'"
		[ -x "$TMP/root/usr/bin/macbook91-wireless-verify" ] &&
			[ -r "$TMP/root/usr/lib/modprobe.d/macbook91-wireless.conf" ] && [ ! -e "$d/build" ] && ok "install layout" || bad "install layout"
		for s in "${sers[@]}"; do
			[ -r "$d/series/$s/kernel/drivers/bluetooth/Kbuild" ] &&
				(cd "$d/series/$s" && sha256sum --quiet -c UPSTREAM.sha256) &&
				[ "$(cat "$d/series/$s/KERNEL-SERIES")" = "$s" ] && ok "series $s: tree complete, manifest verifies" ||
				bad "series $s: tree incomplete or manifest does not verify"
		done
		find "$d" \( -name '*.o' -o -name '*.ko' -o -name '.*.cmd' \) | grep . >/dev/null && bad "build artifacts installed"
	else
		bad "make install: $(tail -n2 "$TMP/install.log")"
	fi
	if python3 packaging/mkdist.py --allow-dirty --out "$TMP/d1" >/dev/null 2>"$TMP/mk.log" &&
		python3 packaging/mkdist.py --allow-dirty --out "$TMP/d2" >/dev/null 2>>"$TMP/mk.log"; then
		cmp -s "$TMP"/d1/*.tar "$TMP"/d2/*.tar && ok "source tarball is reproducible" || bad "tarball differs between runs"
		lst=$(tar -tf "$TMP"/d1/*.tar)
		miss=""
		for s in "${sers[@]}"; do
			for f in UPSTREAM.sha256 KERNEL-SERIES KERNEL-TAG kernel/drivers/bluetooth/Kbuild; do
				grep -E "/series/$s/$f\$" <<<"$lst" >/dev/null || miss+=" $s/$f"
			done
		done
		[ -z "$miss" ] && ok "source tarball holds the tree of every series" || bad "tarball lacks:$miss"
	else
		bad "mkdist: $(tail -n1 "$TMP/mk.log")"
	fi
else
	skip "install and tarball: tree not assembled"
fi

# 7. Licenses: texts, PKGBUILD and the SPDX line of every own file -------------
# The mapping is README.md, "License": files that build the modules are
# GPL-2.0-or-later (GPLv2 wants them with a built module), the hci_uart Kbuild
# GPL-2.0-only (its object list is the kernel's), the rest GPL-3.0-or-later.
spdx_want() {
	case "$1" in
	src/macbook91-wireless/Makefile | src/macbook91-wireless/dkms.conf | packaging/overlay/brcm80211.Kbuild | tests/*.c)
		echo GPL-2.0-or-later ;;
	packaging/overlay/bluetooth.Kbuild) echo GPL-2.0-only ;;
	*) echo GPL-3.0-or-later ;;
	esac
}
lic=""
grep -qx 'Version 3, 29 June 2007' LICENSE || lic+=" LICENSE"
for t in GPL-2.0-only.txt GPL-2.0-or-later.txt; do
	grep -qx 'Version 2, June 1991' "LICENSES/$t" || lic+=" LICENSES/$t"
done
grep -q 'ISC license' LICENSES/ISC || lic+=" LICENSES/ISC"
grep -q '^Permission is hereby granted' LICENSES/MIT || lic+=" LICENSES/MIT"
grep -qx "license=('GPL-3.0-or-later' 'GPL-2.0-or-later' 'GPL-2.0-only' 'ISC' 'MIT')" packaging/arch/PKGBUILD || lic+=" PKGBUILD"
while IFS= read -r -d '' f; do
	head -n 2 "$f" | grep -xE "(#|//) SPDX-License-Identifier: $(spdx_want "$f")" >/dev/null || lic+=" $f"
done < <(tracked -- . ':!release' ':!diag' ':!patches' ':!LICENSE' ':!LICENSES' \
	':!*.md' ':!*.json' ':!VERSION' ':!packaging/arch/.SRCINFO' ':![.]claude/*')
[ -z "$lic" ] && ok "license texts, PKGBUILD licenses and SPDX lines match the mapping" || bad "licenses:$lic"

echo
[ "$fails" = 0 ] && echo "all tests passed" || echo "$fails test(s) failed"
[ "$fails" = 0 ]
