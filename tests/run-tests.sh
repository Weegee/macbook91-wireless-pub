#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Hermetic checks of the repository: no hardware, no root, no network (the
# fetcher runs --offline against build/upstream-cache and is skipped without
# it). Exit status 1 on any failure.
#
# Text interface (house HIG text part, Bash patterns): one line per check on stdout,
# "ok", "FAIL" or "skip" first, then a count line and, last, "all tests
# passed" or "N tests failed". "all tests passed" is read by the release
# checks of the maintainer and stays word for word (STA-1).
# Abweichung von TXT-5: ok / FAIL / skip is the test-report convention of the
# docs (docs/test-status.json counts, STATUS.txt), not a message of a tool.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/macbook91-wireless-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fails=0 oks=0 skips=0
ok() { printf 'ok    %s\n' "$*"; oks=$((oks + 1)); }
bad() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
skip() { printf 'skip  %s\n' "$*"; skips=$((skips + 1)); }
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
mails=$({ tracked -- . ':!patches' | xargs -0 -r grep -IhoE "$mail_re"; grep -h '^From: ' patches/*.patch | grep -oE "$mail_re"; } 2>/dev/null |
	grep -vE '(noreply|no-reply)[.@]|@users\.noreply\.github\.com$|@localhos[t]$|@example\.(com|org)$' | sort -u)
[ -z "$mails" ] && ok "no personal e-mail addresses tracked" || bad "e-mail addresses tracked: $mails"
if tracked -- 'src/macbook91-wireless/series' 'src/macbook91-wireless/kernel' 'src/macbook91-wireless/patches' | grep . >/dev/null; then
	bad "assembled kernel sources are tracked"
else
	ok "assembled kernel sources are not tracked"
fi

# 2. Scripts --------------------------------------------------------------------
scripts=(packaging/fetch-upstream.sh packaging/promote-release.sh packaging/make-package.sh packaging/lib.sh
	tools/macbook91-wireless-verify tools/kernel-series tools/dev-*.sh)
for f in "${scripts[@]}" tests/run-tests.sh packaging/arch/macbook91-wireless.install; do
	bash -n "$f" || bad "syntax: $f"
done
if command -v shellcheck >/dev/null; then
	shellcheck -S warning "${scripts[@]}" &&
		ok "shellcheck" || bad "shellcheck"
else
	skip "shellcheck not installed"
fi
# With pipefail, a grep -q that exits at the first match kills its writer with
# SIGPIPE and the pipeline reports failure: a found match reads as none.
pq=$(awk 'FNR == 1 {prev = ""} {
	if ($0 ~ /\|[[:space:]]*grep -[A-Za-z]*q/ || (prev ~ /\|[[:space:]]*$/ && $0 ~ /^[[:space:]]*grep -[A-Za-z]*q/))
		print FILENAME ":" FNR
	prev = $0 }' "${scripts[@]}" tests/run-tests.sh)
[ -z "$pq" ] && ok "no grep -q at the end of a pipeline" || bad "grep -q ends a pipeline (pipefail): $pq"
python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' packaging/mkdist.py 2>/dev/null &&
	ok "mkdist.py parses" || bad "mkdist.py"

# 3. Patches and lockfile -------------------------------------------------------
if grep -l 'TEST ONLY\|macbook91_halt_fw' patches/*.patch 2>/dev/null | grep . >/dev/null; then
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
	newest[$series]=$tag
done
sers_lock=$(printf '%s\n' "${!newest[@]}" | sort -V | paste -sd' ')
# One patch set for every series: patch files directly in patches/, no
# per-series directory (the fetcher applies the set to every tag with -F0).
npatch=$(find patches -maxdepth 1 -name '*.patch' | wc -l)
if [ "$npatch" -gt 0 ] && [ -z "$(find patches -mindepth 1 -type d)" ]; then
	ok "one patch set ($npatch patches in patches/) for every series ($sers_lock)"
else
	bad "patches/ must hold one set of patch files and no subdirectory"
fi
# The module's dkms.conf: BUILD_EXCLUSIVE_KERNEL is generated at install time
# from the series list, every module is taken from the flat build/ directory.
grep -Fqx 'BUILD_EXCLUSIVE_KERNEL="@SERIES_RE@"' src/macbook91-wireless/dkms.conf &&
	[ "$(grep -c '^BUILT_MODULE_LOCATION\[[0-4]\]="build/"$' src/macbook91-wireless/dkms.conf)" = 5 ] &&
	ok "dkms.conf: series pattern placeholder, 5 modules from build/" || bad "dkms.conf template"
# The module Makefile builds the kernel's own series, and skips a series it does
# not carry with status 0 and no build (fake kernel headers, no compiler run).
mkdir -p "$TMP/skip/kdir/include/generated" "$TMP/skip/tree"
cp src/macbook91-wireless/Makefile "$TMP/skip/tree/"
printf '6.18\n7.2\n' >"$TMP/skip/tree/KERNEL-SERIES"
for rel in 6.12.1-test 7.4.0-test 6.180.1-test; do
	printf '#define UTS_RELEASE "%s"\n' "$rel" >"$TMP/skip/kdir/include/generated/utsrelease.h"
	if out=$(make -s -C "$TMP/skip/tree" KDIR="$TMP/skip/kdir" 2>&1) && grep -F 'nothing built' <<<"$out" >/dev/null &&
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

# 3b. Kernel series: one script for DKMS, the pacman hook, scriptlet, verifier -
# tools/kernel-series is the one reader of KERNEL-SERIES outside the module
# Makefile: make install writes dkms.conf's pattern with it, and the pacman
# hook, the install scriptlet and the verifier ask it. Hermetic: a series list
# and a simulated /usr/lib/modules under $TMP.
KS=tools/kernel-series
ks() { bash "$KS" --series-file "$TMP/ks/KERNEL-SERIES" "$@"; }
mkdir -p "$TMP/ks"
printf '6.18\n7.2\n7.3\n' >"$TMP/ks/KERNEL-SERIES"
[ "$(ks --list)" = '6.18 7.2 7.3' ] && [ "$(ks --dkms-regex)" = '^(6\.18|7\.2|7\.3)\.' ] &&
	ok "kernel-series: series list and dkms.conf pattern" ||
	bad "kernel-series: --list '$(ks --list)', --dkms-regex '$(ks --dkms-regex)'"
ks_rels='6.18.55-2-cachyos-lts 7.2.11-1-cachyos 7.3.0-4-cachyos 7.4.0-1-test 6.180.1-test 6.1.0 x7.3.0'
kfail=""
pat=$(ks --dkms-regex)
for k in $ks_rels; do
	out=$(ks --kernel "$k"); rc=$?
	case "$k" in
	6.18.* | 7.2.* | 7.3.*) want=0 ;;
	*) want=1 ;;
	esac
	[ "$rc" = "$want" ] || kfail+=" $k:exit$rc"
	[ "$rc" = 1 ] && ! grep -F 'not a kernel series macbook91-wireless supports' <<<"$out" >/dev/null && kfail+=" $k:text"
	m=1
	[[ $k =~ $pat ]] && m=0
	[ "$m" = "$rc" ] || kfail+=" $k:dkms-pattern-disagrees"
done
[ -z "$kfail" ] && ok "kernel-series --kernel and the DKMS pattern accept exactly the listed series" ||
	bad "kernel-series --kernel:$kfail"
# --hook: one warning of the package per installed kernel (a directory with
# vmlinuz) of a series not listed, nothing for the others, exit 0 either way.
# The warning goes to stderr, where pacman shows hook output.
for k in 6.18.55-2-cachyos-lts 7.3.0-4-cachyos 7.4.0-1-test 7.5.0-1-test; do mkdir -p "$TMP/ks/modules/$k"; done
for k in 6.18.55-2-cachyos-lts 7.3.0-4-cachyos 7.4.0-1-test; do : >"$TMP/ks/modules/$k/vmlinuz"; done
if out=$(ks --hook --modules-root "$TMP/ks/modules" 2>&1 >"$TMP/ks/hook.out") && [ ! -s "$TMP/ks/hook.out" ] &&
	[ "$(grep -c '^macbook91-wireless: warning: kernel 7.4.0-1-test' <<<"$out")" = 1 ] &&
	! grep -E '^(==>|=+$)' <<<"$out" >/dev/null &&
	grep -F 'kernel 7.4.0-1-test (Linux 7.4) is not a kernel series' <<<"$out" >/dev/null &&
	! grep -E '6\.18\.55|7\.3\.0|7\.5\.0' <<<"$out" >/dev/null; then
	ok "kernel-series --hook warns once, for the installed kernel of the unlisted series 7.4"
else
	bad "kernel-series --hook: $(head -n3 <<<"$out")"
fi
out=$(ks --hook --modules-root "$TMP/ks/none" 2>&1) && [ -z "$out" ] &&
	ok "kernel-series --hook prints nothing without such kernels" || bad "kernel-series --hook without kernels: $out"
bash "$KS" --series-file "$TMP/ks/missing" --list >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && ok "kernel-series exits 2 without a readable list" || bad "kernel-series without a list: exit $rc"
# The pacman hook runs after the transaction, on kernel installs and on this
# package, and cannot abort it.
H=tools/macbook91-wireless-series.hook
if grep -qx 'When = PostTransaction' "$H" && grep -qx 'Target = usr/lib/modules/\*/vmlinuz' "$H" &&
	grep -qx 'Target = usr/src/macbook91-wireless-\*/dkms.conf' "$H" &&
	grep -qx 'Exec = /usr/lib/macbook91-wireless/kernel-series --hook' "$H" && ! grep -q 'AbortOnFail' "$H"; then
	ok "pacman hook: kernel-series --hook after the transaction, cannot abort it"
else
	bad "pacman hook $H"
fi
# The install scriptlet and the verifier ask the script and read no series
# list of their own.
own=$(grep -vh '^[[:space:]]*#' packaging/arch/macbook91-wireless.install tools/macbook91-wireless-verify | grep -c 'KERNEL-SERIES')
if grep -qF '/usr/lib/macbook91-wireless/kernel-series --kernel "$running"' packaging/arch/macbook91-wireless.install &&
	grep -qx 'KERNEL_SERIES=/usr/lib/macbook91-wireless/kernel-series' tools/macbook91-wireless-verify &&
	grep -qF '"$KERNEL_SERIES" --kernel "$running"' tools/macbook91-wireless-verify && [ "$own" = 0 ]; then
	ok "install scriptlet and verifier ask kernel-series, no list of their own"
else
	bad "install scriptlet or verifier: kernel-series not used, or $own own reads of KERNEL-SERIES"
fi
bash -n packaging/arch/macbook91-wireless.install || bad "syntax: packaging/arch/macbook91-wireless.install"
# The package: depends set in package() (.SRCINFO: none in the pkgbase
# section, the LTS headers in the package's own), the current CachyOS
# headers optional, no Arch kernel headers.
SI=packaging/arch/.SRCINFO
if awk '/^pkgname = /{p=1} !p && /^\tdepends = /{bad=1} END{exit bad}' "$SI" &&
	awk '/^pkgname = /{p=1} p && $0 == "\tdepends = linux-cachyos-lts-headers"{f=1} END{exit !f}' "$SI" &&
	grep -q $'^\toptdepends = linux-cachyos-headers: ' "$SI" &&
	! grep -qE $'^\toptdepends = linux-(lts-)?headers' "$SI"; then
	ok ".SRCINFO: depends in package() with the LTS headers, current headers optional, no Arch headers"
else
	bad ".SRCINFO depends: $(grep -n 'depends = ' "$SI" | tr '\n' ' ')"
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
# deliberate change of patches/, the overlays or the v7.2 tag changes this
# value and is recorded here together with the lockfile.
if [ -r "$TMP/tree-7.2/series/7.2/UPSTREAM.sha256" ]; then
	id72=$(sha256sum "$TMP/tree-7.2/series/7.2/UPSTREAM.sha256" | cut -c1-16)
	[ "$id72" = 494451d9a8ce5f25 ] && ok "source ID of series 7.2 is 494451d9a8ce5f25" || bad "source ID of series 7.2 is $id72, pinned 494451d9a8ce5f25"
else
	skip "source ID of series 7.2: not reassembled"
fi

# 4b. Download source: git.kernel.org first, the GitHub mirror when it fails ---
# The fetcher runs against a fake curl and a small invented tree (tag v9.9,
# three files of a few bytes): when git.kernel.org fails, the rest of the run
# comes from the mirror; both failing is the old error, exit status 1; and
# bytes from the mirror go through the same lockfile check as any other bytes.
FB="$TMP/fallback"
mkdir -p "$FB/packaging/overlay" "$FB/patches" "$FB/bin" "$FB/served" "$FB/p/a" "$FB/p/b"
cp packaging/fetch-upstream.sh packaging/lib.sh "$FB/packaging/"
cp packaging/overlay/*.Kbuild "$FB/packaging/overlay/"
fb_files=(drivers/bluetooth/fixture.c drivers/bluetooth/other.h drivers/net/wireless/broadcom/brcm80211/fixture.h)
printf '%s\n' "${fb_files[@]}" >"$FB/packaging/files.list"
: >"$FB/packaging/upstream.lock"
for f in "${fb_files[@]}"; do
	mkdir -p "$FB/served/${f%/*}" "$FB/p/a/${f%/*}" "$FB/p/b/${f%/*}"
	printf 'int a; /* %s */\n' "$f" >"$FB/served/$f"
	printf 'int a; /* %s */\n' "$f" >"$FB/p/a/$f"
	printf 'int b; /* %s */\n' "$f" >"$FB/p/b/$f"
	printf 'v9.9  %s  %s\n' "$(sha256sum <"$FB/served/$f" | cut -d' ' -f1)" "$f" >>"$FB/packaging/upstream.lock"
done
(cd "$FB/p" && diff -u a/drivers/bluetooth/fixture.c b/drivers/bluetooth/fixture.c) >"$FB/patches/fixture.patch" || true
cat >"$FB/bin/curl" <<'FAKECURL'
#!/usr/bin/env bash
# Fake curl: FAKE_KO and FAKE_GH are ok, fail or tamper; every call is logged.
out='' url='' opts=''
while [ $# -gt 0 ]; do
	case "$1" in
	-o) out=$2; shift 2 ;;
	--connect-timeout|--max-time|--retry|--retry-delay) opts="$opts $1=$2"; shift 2 ;;
	-*) shift ;;
	*) url=$1; shift ;;
	esac
done
printf '%s%s\n' "$url" "$opts" >>"$FAKE_LOG"
case "$url" in
https://git.kernel.org/*) mode=$FAKE_KO; path=${url#*/plain/}; path=${path%%\?*} ;;
https://raw.githubusercontent.com/gregkh/linux/*) mode=$FAKE_GH; path=${url#*/gregkh/linux/v9.9/} ;;
*) exit 6 ;;
esac
case "$mode" in
fail) exit 28 ;;
tamper) printf 'tampered\n' >"$out" ;;
*) cp "$FAKE_SERVED/$path" "$out" ;;
esac
FAKECURL
chmod +x "$FB/bin/curl" "$FB/packaging/fetch-upstream.sh"
fb_run() { # fb_run KO GH [fetcher options]: the fetcher in the fixture, fresh cache
	local ko=$1 gh=$2
	shift 2
	rm -rf "$FB/cache" "$FB/out"
	: >"$FB/log"
	FB_RC=0
	PATH="$FB/bin:$PATH" FAKE_KO=$ko FAKE_GH=$gh FAKE_LOG="$FB/log" FAKE_SERVED="$FB/served" \
		"$FB/packaging/fetch-upstream.sh" --tag v9.9 --cache "$FB/cache" --dest "$FB/out" "$@" \
		>"$FB/stdout" 2>"$FB/stderr" || FB_RC=$?
}
fb_count() { grep -c "$1" "$FB/log" || true; }

# The first run records the derived:tree hash of the fixture; the runs after
# it check against it, so a tampered file is caught by the file hash.
fb_run ok fail --accept-new
if [ "$FB_RC" = 0 ] && [ "$(fb_count '^https://git\.kernel\.org/')" = 3 ] &&
	[ "$(fb_count raw\.githubusercontent)" = 0 ] && ! grep -q warning "$FB/stderr" &&
	grep -q -e '--connect-timeout=10' "$FB/log" && grep -q derived:tree "$FB/packaging/upstream.lock"; then
	ok "fetch-upstream.sh: kernel.org answers, the mirror is not asked, no warning"
else
	bad "fetch-upstream.sh: kernel.org answers, the mirror is not asked: exit $FB_RC, $(head -c 300 "$FB/stderr")"
fi

fb_run fail ok
if [ "$FB_RC" = 0 ] && [ -s "$FB/out/UPSTREAM.lock" ] &&
	[ "$(grep -c 'warning: git.kernel.org did not deliver' "$FB/stderr")" = 1 ] &&
	grep -q 'using the GitHub mirror gregkh/linux' "$FB/stderr" &&
	[ "$(fb_count '^https://git\.kernel\.org/')" = 1 ] &&
	[ "$(fb_count '^https://raw\.githubusercontent\.com/gregkh/linux/v9\.9/')" = 3 ] &&
	cmp -s "$FB/served/${fb_files[1]}" "$FB/cache/v9.9/${fb_files[1]}"; then
	ok "fetch-upstream.sh: kernel.org fails once, the mirror serves the rest, files are verified"
else
	bad "fetch-upstream.sh: fallback to the mirror: exit $FB_RC, kernel.org calls $(fb_count '^https://git\.kernel\.org/'), $(head -c 300 "$FB/stderr")"
fi

fb_run fail fail
if [ "$FB_RC" = 1 ] && grep -q 'download failed: ' "$FB/stderr" &&
	grep -q 'git.kernel.org and the GitHub mirror gregkh/linux' "$FB/stderr" && [ ! -e "$FB/out/UPSTREAM.lock" ]; then
	ok "fetch-upstream.sh: both sources failing is an error that names both, exit 1"
else
	bad "fetch-upstream.sh: both sources failing: exit $FB_RC, $(head -c 300 "$FB/stderr")"
fi

fb_run fail tamper
if [ "$FB_RC" = 1 ] && grep -q 'does not match upstream.lock' "$FB/stderr" && [ ! -e "$FB/out/UPSTREAM.lock" ]; then
	ok "fetch-upstream.sh: wrong bytes from the mirror are rejected by the lockfile check"
else
	bad "fetch-upstream.sh: wrong bytes from the mirror: exit $FB_RC, $(head -c 300 "$FB/stderr")"
fi

fb_run fail ok --source github
if [ "$FB_RC" = 0 ] && [ "$(fb_count git\.kernel\.org)" = 0 ] && ! grep -q warning "$FB/stderr"; then
	ok "fetch-upstream.sh --source github never asks kernel.org"
else
	bad "fetch-upstream.sh --source github: exit $FB_RC, $(head -c 300 "$FB/stderr")"
fi

fb_run fail ok --source kernel.org
if [ "$FB_RC" = 1 ] && [ "$(fb_count raw\.githubusercontent)" = 0 ] && grep -q -- '--source github' "$FB/stderr"; then
	ok "fetch-upstream.sh --source kernel.org does not fall back and names the way out"
else
	bad "fetch-upstream.sh --source kernel.org: exit $FB_RC, $(head -c 300 "$FB/stderr")"
fi

"$FB/packaging/fetch-upstream.sh" --source nowhere >/dev/null 2>"$FB/stderr"
FB_RC=$?
if [ "$FB_RC" = 2 ] && grep -q 'unknown source: nowhere' "$FB/stderr"; then
	ok "fetch-upstream.sh --source with an unknown name is a usage error, exit 2"
else
	bad "fetch-upstream.sh --source nowhere: exit $FB_RC, $(head -c 300 "$FB/stderr")"
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
		for k in 6.12.1-1-lts 7.3.0-1-test 7.4.0-1-test 5.15.0 6.1.0 17.2.1; do
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
		[ "$have" = "${sers[*]}" ] && [ "${sers[*]}" = "$sers_lock" ] &&
			ok "installed series trees ($have) equal KERNEL-SERIES and the lock series" ||
			bad "series: trees '$have', KERNEL-SERIES '${sers[*]}', lock '$sers_lock'"
		[ -x "$TMP/root/usr/bin/macbook91-wireless-verify" ] &&
			[ -r "$TMP/root/usr/lib/modprobe.d/macbook91-wireless.conf" ] && [ ! -e "$d/build" ] && ok "install layout" || bad "install layout"
		# The installed tools carry the package version, not a placeholder.
		vv=$(bash "$TMP/root/usr/bin/macbook91-wireless-verify" --version 2>&1)
		kv=$(bash "$TMP/root/usr/lib/macbook91-wireless/kernel-series" --version 2>&1)
		if [ "${vv%%$'\n'*}" = "macbook91-wireless-verify $v" ] &&
			[ "${kv%%$'\n'*}" = "kernel-series (macbook91-wireless-dkms) $v" ] &&
			! grep -F '@PKGVER@' "$TMP/root/usr/bin/macbook91-wireless-verify" "$TMP/root/usr/lib/macbook91-wireless/kernel-series" >/dev/null; then
			ok "installed tools report the package version ($v)"
		else
			bad "installed tools: version '${vv%%$'\n'*}', '${kv%%$'\n'*}'"
		fi
		# kernel-series reads the installed list, and makes the same pattern
		# as dkms.conf's; the hook sorts after 70-dkms-install.hook.
		iks="$TMP/root/usr/lib/macbook91-wireless/kernel-series"
		if [ -x "$iks" ] && grep -qx "SERIES_FILE=/usr/src/macbook91-wireless-$v/KERNEL-SERIES" "$iks" &&
			[ "$(bash "$iks" --series-file "$d/KERNEL-SERIES" --dkms-regex)" = "$pat" ] &&
			cmp -s tools/macbook91-wireless-series.hook "$TMP/root/usr/share/libalpm/hooks/71-macbook91-wireless-series.hook"; then
			ok "installed kernel-series reads the installed list, same pattern as dkms.conf; hook installed"
		else
			bad "installed kernel-series or hook"
		fi
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
		for f in tools/kernel-series tools/macbook91-wireless-series.hook; do
			grep -E "^[^/]+/$f\$" <<<"$lst" >/dev/null || miss+=" $f"
		done
		[ -z "$miss" ] && ok "source tarball holds the tree of every series and the series script" || bad "tarball lacks:$miss"
	else
		bad "mkdist: $(tail -n1 "$TMP/mk.log")"
	fi
else
	skip "install and tarball: tree not assembled"
fi

# Text interface of the tools (house HIG, text part): -h and --help print the help on
# stdout with status 0 and nothing on stderr, -V and --version print
# "prog [(package)] VERSION" as first line, invalid usage ends with status 2, an
# "error:" message on stderr and nothing on stdout, and --help wins over an
# invalid option on the same line.
ver=$(cat VERSION)
tfail=""
for t in tools/macbook91-wireless-verify tools/kernel-series packaging/fetch-upstream.sh packaging/promote-release.sh \
	packaging/make-package.sh tools/dev-suspend-cycle.sh tools/dev-wlan-swap.sh "python3 -I packaging/mkdist.py"; do
	# shellcheck disable=SC2086  # "python3 -I packaging/mkdist.py" is a command with arguments
	set -- $t
	[ "$1" = python3 ] && cmd=("$@") || cmd=(bash "$1")
	prog=$(basename "${!#}")
	h=$("${cmd[@]}" --help 2>"$TMP/t.err"); hrc=$?
	[[ "${h%%$'\n'*}" == "Usage: $prog"* ]] || tfail+=" $prog:--help-usage-line"
	[ "$hrc" = 0 ] && [ ! -s "$TMP/t.err" ] || tfail+=" $prog:--help-rc($hrc)/stderr"
	grep -x 'Examples:' <<<"$h" >/dev/null && grep -x 'Exit status:' <<<"$h" >/dev/null || tfail+=" $prog:help-sections"
	hs=$("${cmd[@]}" -h 2>/dev/null); [ "$hs" = "$h" ] || tfail+=" $prog:-h"
	v=$("${cmd[@]}" --version 2>"$TMP/t.err"); vrc=$?
	[[ "${v%%$'\n'*}" =~ ^$prog\ (\(macbook91-wireless-dkms\)\ )?$ver$ ]] && [ "$vrc" = 0 ] && [ ! -s "$TMP/t.err" ] || tfail+=" $prog:--version"
	[ "$("${cmd[@]}" -V 2>/dev/null)" = "$v" ] || tfail+=" $prog:-V"
	[ "$("${cmd[@]}" --bogus --help 2>/dev/null)" = "$h" ] || tfail+=" $prog:--help-wins"
	if [ "$prog" != make-package.sh ]; then   # its other arguments go to makepkg
		o=$("${cmd[@]}" --bogus 2>"$TMP/t.err"); brc=$?
		[ "$brc" = 2 ] && [ -z "$o" ] && grep -E "^$prog: error: " "$TMP/t.err" >/dev/null || tfail+=" $prog:--bogus($brc)"
	fi
done
set --
[ -z "$tfail" ] && ok "help, version and invalid usage of all tools follow the house HIG, text part" || bad "text interface:$tfail"
# Arguments of the dev helpers are checked before anything is touched.
dfail=""
for a in "mem" "foo 3" "mem x" "mem 0" "mem 2 a"; do
	# shellcheck disable=SC2086
	bash tools/dev-suspend-cycle.sh $a >/dev/null 2>&1; [ $? = 2 ] || dfail+=" suspend-cycle[$a]"
done
for a in "" "--bogus" "--intree extra"; do
	# shellcheck disable=SC2086
	bash tools/dev-wlan-swap.sh $a >/dev/null 2>&1; [ $? = 2 ] || dfail+=" wlan-swap[$a]"
done
bash tools/dev-wlan-swap.sh "$TMP/no-such-dir" >/dev/null 2>"$TMP/t.err"
{ [ $? = 1 ] || [ "$(id -u)" = 0 ]; } && grep -F 'brcmfmac.ko does not exist' "$TMP/t.err" >/dev/null || dfail+=" wlan-swap[no DIR]"
[ -z "$dfail" ] && ok "dev helpers refuse invalid arguments with status 2 before touching anything" || bad "dev helpers:$dfail"
# --reload without root: error with the command to run, status 2, nothing unloaded.
if [ "$(id -u)" != 0 ]; then
	o=$(bash tools/macbook91-wireless-verify --reload 2>"$TMP/t.err"); rc=$?
	if [ "$rc" = 2 ] && [ -z "$o" ] && grep -F 'macbook91-wireless-verify: error: --reload needs root' "$TMP/t.err" >/dev/null &&
		grep -F 'sudo macbook91-wireless-verify --reload' "$TMP/t.err" >/dev/null; then
		ok "verify --reload without root: error, hint with sudo, status 2"
	else
		bad "verify --reload without root: exit $rc, $(head -n2 "$TMP/t.err")"
	fi
else
	skip "verify --reload without root: running as root"
fi

# The verifier's last line (MAS-2, TYP-10): scripts and the hardware gates read
# "PASS|FAIL: N FAIL, M WARN", also when the package is not installed. A stub
# ls that finds no /usr/src/macbook91-wireless-* makes that case the same on
# every host; the verifier reads nothing else of the machine before it ends.
mkdir "$TMP/nols"
printf '#!/bin/sh\nexit 2\n' >"$TMP/nols/ls"
chmod +x "$TMP/nols/ls"
o=$(PATH="$TMP/nols:$PATH" bash tools/macbook91-wireless-verify 2>"$TMP/t.err"); rc=$?
if [ "$rc" = 1 ] && [ "$(tail -n1 <<<"$o")" = "FAIL: 1 FAIL, 0 WARN" ] && [ "$(wc -l <<<"$o")" = 2 ] &&
	grep -q '^FAIL  macbook91-wireless is not installed' <<<"$o" && [ ! -s "$TMP/t.err" ]; then
	ok "verify without the package: FAIL row, totals line, status 1"
else
	bad "verify without the package: exit $rc, output: $(tr '\n' '|' <<<"$o")"
fi
# Colour by role only on a terminal: a pseudo terminal (script) gets escapes
# and the totals line, NO_COLOR and a pipe get plain text.
if command -v script >/dev/null 2>&1; then
	tty=$(PATH="$TMP/nols:$PATH" TERM=xterm script -qec 'bash tools/macbook91-wireless-verify' /dev/null | tr -d '\r')
	nocol=$(PATH="$TMP/nols:$PATH" TERM=xterm NO_COLOR=1 script -qec 'bash tools/macbook91-wireless-verify' /dev/null | tr -d '\r')
	if grep -q $'\e\\[31m' <<<"$tty" && grep -q '1 FAIL, 0 WARN' <<<"$tty" && ! grep -q $'\e' <<<"$o" &&
		[ "$nocol" = "$o" ]; then
		ok "verify: colour on a terminal, plain text in a pipe and with NO_COLOR"
	else
		bad "verify colour: terminal output $(head -n1 <<<"$tty" | cat -v)"
	fi
else
	skip "verify colour: script (util-linux) not found"
fi
# ERF-3: the hints of the verifier are commands that can be copied.
if grep -qF 'missing; install it with: sudo pacman -S linux-firmware-broadcom' tools/macbook91-wireless-verify &&
	grep -qF 'sudo dkms install macbook91-wireless/$pkgver -k $running' tools/macbook91-wireless-verify; then
	ok "verify hints name the command (firmware package, dkms install)"
else
	bad "verify hints: firmware or dkms hint without a command"
fi
# TXT-7, TXT-5: the swap helper writes "WLAN", units with a space, in help and result.
swap_help=$(bash tools/dev-wlan-swap.sh --help)
if grep -qF 'stdout: "WLAN connected after N s"' <<<"$swap_help" &&
	grep -qF 'echo "WLAN connected after ${i} s"' tools/dev-wlan-swap.sh &&
	! grep -qE 'wifi (not )?connected|[0-9]s"' tools/dev-wlan-swap.sh; then
	ok "dev-wlan-swap.sh: WLAN, durations with a space"
else
	bad "dev-wlan-swap.sh: wifi or a duration without a space"
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
	':!*.md' ':!*.json' ':!docs/entwicklung/ansichten' ':!VERSION' ':!packaging/arch/.SRCINFO' ':![.]claude/*')
[ -z "$lic" ] && ok "license texts, PKGBUILD licenses and SPDX lines match the mapping" || bad "licenses:$lic"

echo
printf '%s ok, %s failed, %s skipped\n' "$oks" "$fails" "$skips"
if [ "$fails" = 0 ]; then
	echo "all tests passed"
else
	printf '%s %s failed\n' "$fails" "$([ "$fails" = 1 ] && echo test || echo tests)"
fi
[ "$fails" = 0 ]
