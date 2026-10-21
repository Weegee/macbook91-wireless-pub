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
set -uo pipefail
MODE=$1 N=$2 SLEEP=${3:-20} PAUSE=${4:-30}
mask() { sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/MAC/g'; }
[ "$MODE" = mem ] || [ "$MODE" = freeze ] || { echo "MODE must be mem or freeze" >&2; exit 2; }
fail=0
for i in $(seq 1 "$N"); do
	t0=$(date +%s)
	before=$(cat /sys/power/suspend_stats/success)
	rtcwake -m "$MODE" -s "$SLEEP" >/dev/null 2>&1; rc=$?
	t1=$(date +%s)
	after=$(cat /sys/power/suspend_stats/success)
	slept=no; [ "$after" != "$before" ] && slept=yes
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
	sleep "$PAUSE"
done
echo "RESULT mode=$MODE cycles=$N failed=$fail"
