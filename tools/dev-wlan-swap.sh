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
set -euo pipefail
DEV=0000:02:00.0
P=/sys/bus/pci/devices/$DEV
[ $# -eq 1 ] || { echo "usage: $0 DIR|--intree" >&2; exit 2; }
ip link set wlan0 down 2>/dev/null || true
for m in brcmfmac_wcc brcmfmac_cyw brcmfmac_bca brcmfmac; do
	grep -q "^$m " /proc/modules && rmmod "$m"
done
echo macbook91-none > "$P/driver_override"
if [ "$1" = --intree ]; then
	modprobe brcmfmac ${BRCMFMAC_PARAMS:-}; modprobe brcmfmac-wcc
else
	insmod "$1/brcmfmac.ko" ${BRCMFMAC_PARAMS:-}; insmod "$1/wcc/brcmfmac-wcc.ko"
fi
echo > "$P/driver_override"
echo "$DEV" > /sys/bus/pci/drivers/brcmfmac/bind
for i in $(seq 1 30); do
	nmcli -t -f TYPE,STATE dev | grep -x 'wifi:connected' >/dev/null && { echo "wifi connected after ${i}s"; exit 0; }
	sleep 1
done
echo "wifi not connected after 30s" >&2; exit 1
