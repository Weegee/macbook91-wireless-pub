# Kernel series and firmware

DKMS builds the modules for every installed kernel of a supported series and
needs that kernel's headers. Print the list:

```fish
/usr/lib/macbook91-wireless/kernel-series --list
```

Output on the test machine, 2026-11-09:

```text
6.18 7.2 7.3
```

The CachyOS LTS kernel is the default (package `linux-cachyos-lts-headers`).
The current CachyOS series is supported too; for it install
`linux-cachyos-headers`, which brings the clang, lld and llvm its kernel needs.
A kernel of any other series keeps its stock drivers: DKMS skips it, a pacman
hook warns after every kernel install, and `macbook91-wireless-verify` reports
a FAIL.

| Series | Kernel (tested) | Status |
| --- | --- | --- |
| 7.3 | `7.3.0-4-cachyos` (clang) | all five modules build; verifier on `7.3.3-1-cachyos` on the MacBook9,1, 2026-11-09: 0 FAIL, 0 WARN, WLAN up. Suspend/resume, Bluetooth function and rebind recovery NOT VERIFIED |
| 7.2 | `7.2.11-1-cachyos` (clang) | run on the MacBook9,1 up to release 20261015.01; later releases carry the result over |
| 6.18 | `6.18.55-2-cachyos-lts` (gcc) | release 20261020.02: verifier 0 FAIL, 0 WARN, WLAN up. Suspend/resume, Bluetooth function and rebind recovery NOT VERIFIED |

Every test run is in [test-status.json](test-status.json).

## Firmware

There is no separate firmware package. The WLAN firmware is
`brcm/brcmfmac4350c2-pcie.bin` from `linux-firmware-broadcom`, the only
FullMAC firmware for this chip. The firmware of macOS and Boot Camp is the BMAC
(SoftMAC) variant, which `brcmfmac` cannot run. The Bluetooth controller runs
on its ROM. Details: [FINDINGS.md](FINDINGS.md#firmware).
