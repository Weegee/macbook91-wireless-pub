#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Development helper, not packaged: N suspend cycles through rtcwake
# (bypasses logind, so the run's sleep inhibitor does not block it),
# then per cycle: did the system sleep, seconds until WLAN is connected again,
# hci0 state, and every kernel message of priority warning or worse about
# WLAN or Bluetooth.
#   tools/dev-suspend-cycle.sh MODE N [SLEEP] [PAUSE]   MODE: mem | freeze
# Writes a report to stdout; MAC addresses are masked. Needs root (rtcwake).
#
# Text interface (house text HIG, Bash patterns): the report (one "cycle ..."
# line per cycle and the "RESULT ..." line) is the result on stdout and stays
# as it is, because the run protocols quote it. Progress and failures are
# "dev-suspend-cycle.sh: text" lines on stderr. Exit status 0 / 1 / 2: every
# cycle passed, a cycle failed, invalid usage. Usage: --help.
set -uo pipefail

PROG=dev-suspend-cycle.sh
usage() {
	cat <<USAGE
Usage: $PROG MODE N [SLEEP] [PAUSE]

Run N suspend cycles through rtcwake (this bypasses logind, so the sleep
inhibitor of a run does not block it). Per cycle the report says whether the
system slept, how many seconds until WLAN is connected again, the state of
hci0 and every kernel message of priority warning or worse about WLAN or
Bluetooth. MAC addresses are masked. Development helper, not packaged.

Examples:
  sudo tools/$PROG mem 5
  sudo tools/$PROG freeze 3 20 30

Arguments:
  MODE    mem or freeze
  N       number of cycles, at least 1
  SLEEP   seconds asleep per cycle (default 20)
  PAUSE   seconds between cycles (default 30)

Options:
  -h, --help      show this help and exit
  -V, --version   show the version and exit

Output:
  stdout   one "cycle i/N ..." line per cycle (kernel messages indented below
           it), then "RESULT mode=... cycles=... failed=..."
  stderr   progress

Exit status:
  0  every cycle slept, WLAN came back and no warning was logged
  1  at least one cycle failed
  2  invalid usage, or not run as root

Docs and bug reports: $HOMEPAGE
USAGE
}

# shellcheck source=../packaging/lib.sh
. "$(dirname "$0")/../packaging/lib.sh"
help_or_version "$@"

[ $# -ge 2 ] || usage_error "MODE and N are required" "Example: sudo tools/$PROG mem 5"
[ $# -le 4 ] || usage_error "too many arguments: $5"
MODE=$1 N=$2 SLEEP=${3:-20} PAUSE=${4:-30}
[ "$MODE" = mem ] || [ "$MODE" = freeze ] || usage_error "MODE must be mem or freeze, not '$MODE'"
need_number N "$N"
[ "$N" -ge 1 ] || usage_error "N must be at least 1"
need_number SLEEP "$SLEEP"
need_number PAUSE "$PAUSE"
[ "$(id -u)" -eq 0 ] || { err "rtcwake needs root" "Run: sudo tools/$PROG $MODE $N"; exit 2; }
trap_signals

mask() { sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/MAC/g'; }
fail=0
for i in $(seq 1 "$N"); do
	step "cycle $i of $N: suspending ($MODE) for ${SLEEP} s (Ctrl+C cancels)"
	t0=$(date +%s)
	before=$(cat /sys/power/suspend_stats/success)
	rtcwake -m "$MODE" -s "$SLEEP" >/dev/null 2>&1; rc=$?
	t1=$(date +%s)
	after=$(cat /sys/power/suspend_stats/success)
	slept=no; [ "$after" != "$before" ] && slept=yes
	step "cycle $i of $N: resumed, waiting up to 60 s for WLAN"
	w=-1
	for s in $(seq 1 60); do
		nmcli -t -f TYPE,STATE dev | grep -x 'wifi:connected' >/dev/null && { w=$s; break; }
		sleep 1
	done
	hci=$(bluetoothctl show 2>/dev/null | grep -oE 'PowerState: [a-z-]+')
	msgs=$(journalctl -k --since "@$t0" --no-pager -p warning -o cat | grep -iE 'brcm|ieee80211|bluetooth|hci|wlan|02:00\.0' | grep -v 'UFW BLOCK' | mask)
	n=$(printf '%s' "$msgs" | grep -c . || true)
	echo "cycle $i/$N mode=$MODE rtcwake_rc=$rc slept=$slept wake_s=$((t1-t0)) wifi_after_s=$w bt=[$hci] warn_msgs=$n"
	[ -n "$msgs" ] && printf '%s\n' "$msgs" | sed 's/^/    /'
	{ [ "$slept" = yes ] && [ "$w" -ge 0 ] && [ "$n" -eq 0 ]; } || fail=$((fail+1))
	step "cycle $i of $N: pausing ${PAUSE} s"
	sleep "$PAUSE"
done
echo "RESULT mode=$MODE cycles=$N failed=$fail"
[ "$fail" -eq 0 ] || { step "$fail of $N cycles failed (see the report above)"; exit 1; }
