#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Development helper, not packaged: replace the loaded brcmfmac (and
# brcmfmac-wcc) by the modules in DIR without the device probing in
# between, then bind the device and wait for NetworkManager.
#   tools/dev-wlan-swap.sh DIR      DIR holds brcmfmac.ko and wcc/brcmfmac-wcc.ko
#   tools/dev-wlan-swap.sh --intree back to what modprobe loads for the running
#                                    kernel: with macbook91-wireless-dkms
#                                    installed the package's modules, not stock
# BRCMFMAC_PARAMS="name=value ..." passes module parameters to brcmfmac.
# Needs root (rmmod, insmod, driver bind).
#
# Text interface (house text HIG, Bash patterns): "wifi connected after Ns" is
# the result on stdout; steps and failures are "dev-wlan-swap.sh: text" lines
# on stderr. Everything that can be checked is checked before the first module
# is unloaded. Exit status 0 / 1 / 2: connected, failed, invalid usage. Usage:
# --help.
set -euo pipefail

PROG=dev-wlan-swap.sh
usage() {
	cat <<USAGE
Usage: $PROG DIR | --intree

Replace the loaded brcmfmac (and brcmfmac-wcc) by the modules in DIR without
the device probing in between, then bind the device and wait up to 30 s for
NetworkManager. WLAN is down for the time of the swap. Development helper, not
packaged.

Examples:
  sudo tools/$PROG ./modules
  sudo tools/$PROG --intree

Arguments:
  DIR        holds brcmfmac.ko and wcc/brcmfmac-wcc.ko
  --intree   go back to what modprobe loads for the running kernel: with
             macbook91-wireless-dkms installed the package's modules, not stock

Options:
  -h, --help      show this help and exit
  -V, --version   show the version and exit

Environment:
  BRCMFMAC_PARAMS   module parameters for brcmfmac, "name=value ..."

Exit status:
  0  WLAN connected (stdout: "wifi connected after Ns")
  1  a step failed, or WLAN not connected after 30 s
  2  invalid usage, or not run as root

Docs and bug reports: $HOMEPAGE
USAGE
}

# shellcheck source=../packaging/lib.sh
. "$(dirname "$0")/../packaging/lib.sh"
help_or_version "$@"

DEV=0000:02:00.0
P=/sys/bus/pci/devices/$DEV
[ $# -le 1 ] || usage_error "too many arguments: $2"
[ $# -eq 1 ] || usage_error "DIR or --intree is required" "Example: sudo tools/$PROG --intree"
case $1 in
-*) [ "$1" = --intree ] || usage_error "unknown option: $1" ;;
esac
RESTORE="Restore the driver with: sudo tools/$PROG --intree"

# Check everything before the first module is unloaded (EIN-6).
if [ "$1" = --intree ]; then
	modprobe -n brcmfmac >/dev/null 2>&1 || die "modprobe cannot find brcmfmac for kernel $(uname -r)"
else
	[ -f "$1/brcmfmac.ko" ] || die "$1/brcmfmac.ko does not exist" "DIR must hold brcmfmac.ko and wcc/brcmfmac-wcc.ko"
	[ -f "$1/wcc/brcmfmac-wcc.ko" ] || die "$1/wcc/brcmfmac-wcc.ko does not exist" "DIR must hold brcmfmac.ko and wcc/brcmfmac-wcc.ko"
fi
[ -d "$P" ] || die "the PCI device $DEV does not exist" "This helper is for the MacBook9,1 WLAN chip only"
[ "$(id -u)" -eq 0 ] || { err "unloading and binding drivers needs root" "Run: sudo tools/$PROG $1"; exit 2; }

# Cancelled between the first unload and the end: say how to get WLAN back.
SWAPPING=0
on_cancel() {
	trap - "$1"
	printf '\n%s: cancelled\n' "$PROG" >&2
	[ "$SWAPPING" = 0 ] || printf '  The WLAN driver may be unloaded. %s\n' "$RESTORE" >&2
	kill -s "$1" "$$"
}
trap 'on_cancel INT' INT
trap 'on_cancel TERM' TERM
swap_failed() { err "$1" "The WLAN driver may be unloaded. $RESTORE"; exit 1; }

step "unloading brcmfmac; WLAN is down until the device is bound again"
SWAPPING=1
ip link set wlan0 down 2>/dev/null || true
for m in brcmfmac_wcc brcmfmac_cyw brcmfmac_bca brcmfmac; do
	if grep "^$m " /proc/modules >/dev/null; then
		rmmod "$m" || swap_failed "cannot unload $m"
		step "unloaded $m"
	fi
done
echo macbook91-none > "$P/driver_override"
if [ "$1" = --intree ]; then
	# shellcheck disable=SC2086  # BRCMFMAC_PARAMS is a list of parameters
	{ modprobe brcmfmac ${BRCMFMAC_PARAMS:-} && modprobe brcmfmac-wcc; } || swap_failed "cannot load the modules of kernel $(uname -r)"
	step "loaded the modules modprobe finds for kernel $(uname -r)"
else
	# shellcheck disable=SC2086
	{ insmod "$1/brcmfmac.ko" ${BRCMFMAC_PARAMS:-} && insmod "$1/wcc/brcmfmac-wcc.ko"; } || swap_failed "cannot load the modules from $1"
	step "loaded the modules from $1"
fi
echo > "$P/driver_override"
echo "$DEV" > /sys/bus/pci/drivers/brcmfmac/bind || swap_failed "cannot bind $DEV to brcmfmac"
step "bound $DEV; waiting up to 30 s for NetworkManager (Ctrl+C cancels)"
SWAPPING=0
for i in $(seq 1 30); do
	nmcli -t -f TYPE,STATE dev | grep -x 'wifi:connected' >/dev/null && { echo "wifi connected after ${i}s"; exit 0; }
	[ $((i % 10)) -ne 0 ] || step "still waiting after $i of 30 s"
	sleep 1
done
err "wifi not connected after 30s" "Check: nmcli dev status; journalctl -k -b -n 30"
exit 1
