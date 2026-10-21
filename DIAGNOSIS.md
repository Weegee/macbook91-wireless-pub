# DIAGNOSIS: WLAN failure after suspend cycles on the MacBook9,1 (2026-10-13)

Collected read-only, during tests of the camera project (macbook91-facetimehd). Nothing about the WLAN was changed. Raw data: `diag/2026-10-13/` (MAC addresses redacted).

Markers: **VERIFIED** (backed by a log or measurement), **NOT VERIFIED** (plausible, not checked), **HYPOTHESIS** (attempted explanation, open), **REPORTED** (statement by the maintainer, not visible in the log).

## Summary

After six successful suspend cycles in about four minutes, the firmware of the BCM4350 stalled 1.6 s after the resume from the sixth cycle (S3). After that every command to the firmware failed with `-EIO`, and the WLAN driver aborted every further suspend (`brcmf_pcie_pm_enter_D3: Timeout`). A manual module reload failed because the chip returns only `0xffffffff` to MMIO accesses. Since then the card has no driver, and the MacBook9,1 is on the network only through USB Ethernet.

## System

| Item | Value |
|---|---|
| Device | MacBook9,1 (A1534), CachyOS |
| Kernel | 7.2.9-1-cachyos |
| WLAN | Broadcom BCM4350 `14e4:43a3` rev 05, subsystem Apple `106b:0158`, PCI 02:00.0 |
| Root port | 00:1d.0 = ACPI `\_SB_.PCI0.RP09`, node `ARPT` |
| Neighbour | camera at 00:1d.1 = `RP10` (same PCH port block 1d.x) |
| Driver | brcmfmac (PCIe, msgbuf), no module parameters, no modprobe.d entries |
| Firmware | `brcm/brcmfmac4350c2-pcie`, reports `7.35.180.133 (r602372)` of 2015-11-26, from linux-firmware(-broadcom) 1:20260916-1 |
| CLM blob | missing (`no clm_blob available`), channels possibly limited; unrelated to the failure |
| Network | NetworkManager 1.58.1, wpa_supplicant 2.12 and iwd 3.12 installed |
| Sleep | `mem_sleep` = `s2idle [deep]` |

## Timeline (kernel monotonic, wall clock CEST)

| Monotonic | Wall clock | Event |
|---|---|---|
| 14.8 s | boot | brcmfmac loads the firmware, `phy0` |
| 38 027 s | approx. 09:21 | S3 (old camera driver): WLAN resume through the cold path, firmware reloaded, `phy1` |
| 38 041 s | | S3: cold path again, `phy2` |
| 38 052 / 38 069 s | | s2idle ok; S3 attempt aborted by the old camera driver with `-EBUSY` |
| 40 753–40 969 s | 10:07–10:11 | **6 suspends ok** (S3, S3, s2idle, S3, s2idle, S3), WLAN stays `phy2`, no firmware reload |
| **40 971 s** | **10:11:44** | **first firmware timeout** `brcmf_msgbuf_query_dcmd: Timeout on response for query command`, 1.6 s after the resume from S3 no. 6 |
| 40 971–41 100 s | | follow-on errors: chanspec, tx_power, escan, multicast, set_power_mgmt (`-EIO`), later `Failed to reserve space in commonring` (220×), `-ENOMEM` |
| 41 045 s | | S3: `brcmf_set_mpc: fail to set mpc`, "Some devices failed to suspend" |
| 41 072–41 159 s | | 4× S3 attempt: `brcmf_pcie_pm_enter_D3: Timeout on response for entering D3 substate`, `pci_pm_suspend returns -5`, suspend aborted |
| 41 342 / 41 366 s | | `add iface p2p-dev-wlan0 … err=-12` |
| 41 435 s | 10:19:28 | `deregistering interface driver brcmfmac` (manual) |
| 41 444 s | 10:19:37 | reload: `brcmf_chip_recognition: MMIO read failed: 0xffffffff`, `brcmf_pcie_probe: failed 14e4:43a3` |

Source: `diag/2026-10-13/kernel-wifi-pm-boot.log`, `timeline-wallclock.log`, `suspend-tests.txt`.

## Findings

1. **VERIFIED:** the failure began with a firmware hang after a resume through the warm path (no firmware reload, same `phy2`). The first two S3 resumes of the boot went through the cold path (firmware reloaded) and had no consequences.
2. **VERIFIED:** from the hang on, brcmfmac blocks every S3: `brcmf_pcie_pm_enter_D3` waits in vain for the firmware's D3 acknowledgement and returns `-EIO`; the kernel aborts the suspend (`rtcwake: Schreibfehler` [write error]). A laptop with hung WLAN therefore no longer sleeps.
3. **VERIFIED:** a module reload does not restore the device. Config space is readable (`ID 43a314e4`, link 2.5 GT/s x1 active), but BAR accesses return `0xffffffff`. The chip is dead internally (backplane/ARM core), not the PCIe link.
4. **REPORTED:** the maintainer also tried a reset. Nothing about it shows in the kernel log; which reset (sysfs `reset`, remove/rescan) is open.
5. **VERIFIED:** current state (after the reload attempt): no driver bound, `enable=0`, CMD=0000, `reset_method=bus`, `d3cold_allowed=1`, root port 00:1d.0 in runtime D3hot (PMCSR 0x0103). See `pci-state.txt`.
6. **VERIFIED (DSDT):** `ARPT` has no power control (no `_PS0/_PS3`, no `_PR3`, no GPIO, no `CMPE` counterpart), only `_PRW` (GPE 0x69) and fields in its own config space. The driver therefore cannot cut the power of the WLAN chip through ACPI; the camera method `CMPE` only accesses RP10 fields and GPIO 0x02000010. Shared ACPI resources between WLAN and camera: none found.

## Further factors on the test machine

- **VERIFIED:** all suspends of 2026-10-13 went through `rtcwake` (writes `/sys/power/state` directly) and thus **bypassed systemd-sleep**. The hooks in `/usr/lib/systemd/system-sleep/` (`tlp`, a local sleep hook, `atop-pm.sh`, `sysstat.sleep`) did not run; the journal has no `SLEEPHACK` entry. An everyday suspend through KDE or the lid takes a different path; the results do not carry over directly.
- **VERIFIED:** the local sleep hook only toggles the wake source `LID0` and does not touch WLAN/PCI. It belongs to no package, although its header comment says it is not installed.
- **VERIFIED:** TLP is active (`tlp` enabled), only `WIFI_PWR_ON_BAT=off` is set; runtime PM and ASPM run with TLP defaults. The power supply was connected during the tests.

## Hypotheses (open)

- **H1, HYPOTHESIS:** brcmfmac's warm-path resume with the BCM4350 firmware 7.35.180.133 (2015) is unreliable. Whether upstream reports or fixes for it exist has not been researched yet.
- **H2, HYPOTHESIS:** interaction with the new camera driver. On s2idle and on every resume it switches the neighbouring root port RP10 to D3 and back through ACPI (L2/L3 handshake, GPIO). ACPI has no shared resource; a coupling through the shared PCH port block 1d.x is NOT VERIFIED. Counter-argument: the first 5 cycles with this camera driver ran without WLAN errors.
- **H3, HYPOTHESIS:** load pattern: 6 suspends in 4 minutes, some with a running camera stream, without WLAN being able to reassociate in between.
- **H4, HYPOTHESIS:** difference between the cold and the warm path: whether brcmfmac resumes cold or warm after S3 depends on whether the chip kept power during sleep (aux power, wake configuration). Why the first two S3 ran cold and the later ones warm is unexplained.

## Consequences for the camera project

Of the 12 suspend attempts of the camera test on 2026-10-13, only the first 6 actually slept; brcmfmac aborted the other 6. In the camera project they count only as a test of the abort path (the camera survived them), not as a suspend test.

## Unknown

- Whether a reboot reliably brings WLAN back: **VERIFIED for one case** (reboot on 2026-10-13 approx. 10:47, afterwards brcmfmac bound, `wlan0` connected). During the same reboot an unattended update brought kernel 7.2.9-2 instead of 7.2.9-1; later measurements therefore run on a different kernel build.
- Whether a secondary bus reset through RP09 (`reset_method=bus`) or a D3cold cycle brings the chip back without a reboot.
- Whether the failure occurs the same way without the camera driver loaded (control experiment missing).
- How often the failure occurs in daily use without camera tests.
