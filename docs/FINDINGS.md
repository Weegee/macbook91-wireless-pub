# Findings: WLAN and Bluetooth of the MacBook9,1

As of 2026-10-15, kernel 7.2.9-2-cachyos (the test machine). Raw data such as btmon captures is
not part of this repository; `diag/2026-10-13/` and `DIAGNOSIS.md` hold the
redacted first diagnosis.

Markers: **VERIFIED** (log or measurement), **NOT VERIFIED** (plausible,
not checked), **REFUTED**, **HYPOTHESIS**, **REPORTED** (statement by the
maintainer).

## Hardware

| | |
| --- | --- |
| WLAN | Broadcom BCM4350, PCI revision 05 (brcmfmac: chip BCM4350/5), PCIe `14e4:43a3` at 02:00.0 behind root port RP09, driver `brcmfmac` (msgbuf), reset only through the bus (no FLR, `NoSoftRst+`) |
| WLAN firmware | `brcm/brcmfmac4350c2-pcie.bin` 7.35.180.133 from `linux-firmware-broadcom`, CLM built in (API 12.0, Data 7.9.9) |
| Bluetooth | BCM4350C0, UART (LPSS dw-apb-uart, max. 3 Mbit/s), ACPI `BCM2E7C`, ROM 003.001.134 build 1532, driver `hci_uart` (`hci_uart_bcm`) |
| ACPI BT | `_DSM` baud = 3000000, power through `BTPU`/`BTPD`, `BTLP`, wake through `_PRW` (GPE), **no** interrupt in `_CRS`, hence no host wake and no LPM |

## WLAN

### Failure after suspend

- **VERIFIED** (journal of boot −2, `DIAGNOSIS.md`): after several suspends
  the firmware stops answering the D3 handshake; then command timeouts,
  220× `commonring` errors, 5 aborted suspends. WLAN stayed gone until a
  reboot. **REPORTED**: "WLAN gone after suspend".
- **VERIFIED**: `unbind`, a secondary bus reset through the bridge and
  `bind` bring the device back without a reboot (reconnect 6 to 11 s).
- Fix (patches 0003, 0004, 0005, 0007):
  - `pm_reset` (on by default): before sleep the device state is torn
    down, after resume a freshly reset chip is probed. The firmware's
    error-prone D3 handshake is gone; a D3 timeout no longer aborts the
    suspend.
  - `reset_rebind` (on by default): two command timeouts in a row or a
    reset request from the driver trigger unbind, bus reset and probe, at
    most three times in ten minutes.
  - PCI reset handlers: the driver tears itself down before a function
    reset and probes again afterwards.
- Consequence of `pm_reset` (**VERIFIED**, source of 0003): before sleep the
  device is removed and the chip reset; no firmware runs during sleep, so
  there is no Wake-on-WLAN (WoWLAN). Whoever needs it sets `pm_reset=0` and
  accepts the firmware's D3 path.
- **VERIFIED** live (test module with a debug hook, not shipped):
  artificially halted firmware → 2 timeouts → "Firmware does not respond,
  recovering" → WLAN back after about 16 s; reset through debugfs → 11 s.
- **VERIFIED** live: 3× S3 and 3× s2idle with the test module, 2× S3 and
  2× s2idle with patched Bluetooth, 1× S3 and 1× s2idle with the installed
  package 20261013.01. 2× S3 with 20261014.01 in daily use (2026-10-14),
  firmware reloaded on each resume. Slept every time, WLAN connected after
  5 to 6 s, Bluetooth on, 0 warnings.
- **NOT VERIFIED**: whether the bus reset also recovers a chip whose
  backplane only returns `0xffffffff` (seen in the journal, not triggered
  reproducibly).
- **NOT RUN**: long mixed suspend series (target about 100 cycles).
  Postponed by the maintainer.
- **NOT RUN**: hibernation. 0003 also changes freeze, thaw and restore
  (device removed before the image, probed again afterwards); hibernation
  is not set up on the test machine (no `resume=`).

### Firmware

- **VERIFIED** (strings): the firmware in macOS 12 (AirPortBrcmNIC,
  `dlarray_4350pci` 7.77.0.0) and in Boot Camp 041-88396 (`bcmwl63a.sys`,
  7.35.118.54) is the BMAC variant in both cases (`4350pci-bmac`), without
  the msgbuf protocol. `brcmfmac` cannot run it.
- Consequence: `linux-firmware` has the only FullMAC firmware for this
  chip; a separate firmware package would have nothing better to ship.
- Regulatory domain: section "Regulatory domain".

### Regulatory domain

- **VERIFIED** (journal, once per boot): `cfg80211: Process
  '/usr/bin/set-wireless-regdom' failed with exit code 1`. No line is active
  in `/etc/conf.d/wireless-regdom` (a file of `wireless-regdb`); the script
  ends with `[ -n "${WIRELESS_REGDOM}" ] && iw reg set …` and then returns 1.
  Harmless.
- **VERIFIED**: on CachyOS, `cachyos-iw-set-regdomain.service`
  (`cachyos-settings`) already sets the domain DE from the time zone, about
  2 s after cfg80211 is loaded. `iw reg get`: `global country DE:
  DFS-ETSI`.
- User step (cannot be packaged: the script reads only this file of another
  package): enable `#WIRELESS_REGDOM="DE"` in `/etc/conf.d/wireless-regdom`.
  The udev message goes away, and DE applies from the moment cfg80211 is
  loaded. **VERIFIED** (`iw reg set DE` on the running system, as udev runs
  it): domain and channel list unchanged (live test T5,
  `diag/2026-10-14/live-tests.md`). The file itself was not changed; that
  the udev message disappears afterwards is **NOT VERIFIED** but follows
  from the script.
- **VERIFIED** (source v7.2.9, `brcmf_cfg80211_reg_notifier()`,
  `brcmf_translate_country_code()`): on x86, brcmfmac does not pass the
  country code to the firmware of the BCM4350. There is no country code
  table (only through devicetree or platform data), and the BCM4350 is not
  in the driver's ISO 3166 fallback list (43430, 4345, 4356, 43602); the
  translation ends with `-EINVAL`. The firmware keeps its built-in country
  code (which one is **NOT VERIFIED**); `phy#0` shows the driver's own
  domain `99` (`REGULATORY_CUSTOM_REG`).
- **VERIFIED** (`iw phy phy0 channels`, DE): 2.4 GHz channels 1 to 13
  (14 disabled), 5 GHz 34 to 165, radar detection on 52 to 64 and 100 to
  144, no No-IR. cfg80211 limits the firmware's channel list to DE;
  `WIRELESS_REGDOM` changes nothing in the firmware.
- The maintainer's decision (2026-10-14): no patch that gives the firmware a
  country code.
- **VERIFIED**: `Country code iovar returned err = -5` on resume came from
  the stock path (the notifier queries the firmware while the bus is torn
  down); in the boot of 2026-10-13 20:22 with `pm_reset`, 0 hits in 128
  resumes.

### Journal noise

| Message | Source | Status | Action |
| --- | --- | --- | --- |
| Hundreds of errors while a dead device is torn down | brcmfmac | VERIFIED | 0002: silent while the teardown is intended |
| `no clm_blob available`, `no txcap_blob available`, flow-ring timeouts on deletion | brcmfmac | VERIFIED normal for this firmware (CLM built in) | 0006: debug level |
| `using brcm/...` and others as errors | brcmfmac with `CONFIG_BRCMDBG` (CachyOS) | VERIFIED: `brcmf_info` was `brcmf_err` there | 0008: info level |
| "resetting"/"reset done" on every resume | PCI core | VERIFIED | 0007: reset handlers |
| `p2p-dev-wlan0` errors, "Could not read interface p2p-dev-wlan0", IPv4 forwarding warnings | wpa_supplicant, NetworkManager | VERIFIED | P2P off (`feature_disable=0x10`, modprobe.d) |
| `multicast RX registrations are not supported` (2× per connection) | wpa_supplicant (kernel extack) | VERIFIED harmless | none: the driver cannot do multicast registrations, and faking them would be wrong |
| `P2PDeviceConfig getter failed` | wpa_supplicant D-Bus | VERIFIED harmless, a consequence of P2P off | none |
| `SetLinkDomains ... Link not known` | NetworkManager/resolved | VERIFIED harmless | none |
| `unlocked secondary bus reset via: __pci_reset_function_locked` at `00:1d.0`, once per boot on the first resume | PCI core, triggered by the intended reset of 0003 (`pm_reset`) | VERIFIED: 0003 did not lock the bridge during the reset (boot 2026-10-13 20:22: one line in 128 resumes) | 0011 locks the bridge's configuration; VERIFIED: boot 2026-10-14 12:29 with 20261014.01, 2 resumes, 0 hits |
| `'atop' uses wireless extensions which will stop working for Wi-Fi 7 hardware` | kernel, triggered by atop | VERIFIED harmless (once per boot) | none: concerns atop, not brcmfmac |
| `set-wireless-regdom failed with exit code 1` | udev, wireless-regdb | VERIFIED harmless | user step (section "Regulatory domain") |

### Sleep hooks

- **VERIFIED** (2026-10-20): active are `macbook91-lid-wake` (package
  macbook91-hw-fixes; a local sleep hook, listed as of 2026-10-15, is
  no longer installed), `tlp`, `atop-pm.sh`, `sysstat.sleep`; none of them
  unloads brcmfmac or hci_uart. An older hack (unload brcmfmac before sleep)
  exists only as a file in a backup and is not installed; `pm_reset` makes
  it unnecessary. `macbook91-wireless-verify` warns if such a hook shows up.

## Bluetooth

- **VERIFIED** (btmon): before the reset, the setup sends a speed change to
  3 Mbit/s, which the controller already runs at according to ACPI; it
  answers "Command Disallowed" (`-16`, two error lines per start).
- **VERIFIED**: for the BCM4350C0, btbcm looks only for `brcm/BCM.hcd`,
  finds nothing and logs an error; the setup then ended early.
- **VERIFIED** (strings): neither macOS 12 (BaseSystem: `/usr/share/firmware/bluetooth`,
  BlueTool, bluetoothd) nor Boot Camp 041-88396 (BtwSerialBus) contains a
  patch for the BCM4350C0. **NOT VERIFIED** for older macOS versions.
  According to this finding, Apple runs the controller on its ROM.
- Fix 0010: on Macs no patch search, no speed change before the setup and
  none when the target and initial speeds are equal; the warnings about the
  Mac's ACPI layout are gone. The parameter `apple_patchram` restores the
  search.
- **VERIFIED** (btmon): 268 of 434 LE advertising reports carry set reserved
  bits in the event type (0x1x, 0x2x); the kernel discards them ("unknown
  advertising packet type").
- Fix 0009: reserved bits are cleared on Macs, only for a valid legacy
  type. Host test with ASan/UBSan in `tests/`.
- Revision 20261015.01: 0009 copies the flag into `bcm_data` on open, and
  the receive path no longer reads `bcm->dev` (the upstream path checks
  this device only under a lock); 0010 leaves out the speed change only on
  Macs, other machines keep upstream behaviour.
  Live test (`diag/2026-10-15/live-tests.md`): **VERIFIED**, init without warnings, 30 s LE scan without "unknown advertising packet type".
- **VERIFIED** A/B, 30 s LE scan each: stock 12 devices and 25 warnings,
  patched 34 to 50 devices and 0 warnings.
- **VERIFIED**: Bluetooth stays on across S3 and s2idle, scanning is normal
  afterwards.
- **NOT RUN**: audio (A2DP/HFP) and input devices across suspend; no device
  is paired. **REPORTED**: problems with BT audio and BT input devices after
  suspend.
- Note (as of 2026-10-15): `rtkit-daemon` was missing; PipeWire then ran
  without real-time priority, which can encourage dropouts in BT audio
  (**HYPOTHESIS**, a recommendation; the audio configuration was not
  changed). Since 2026-10-19 `rtkit` is installed and `rtkit-daemon` active
  (**VERIFIED** 2026-10-20).
- Bluetooth was soft-blocked through a KDE setting (the maintainer's choice);
  unblocked for the tests, restored afterwards.

### Message `Failed to set mode: Failed (0x03)`

- **VERIFIED** (journal): bluetoothd logs it twice per boot, shortly after
  it starts and at login; at login kded6 also logs
  `PendingCall Error: "Failed"`.
- **REPORTED**: Bluetooth is switched off through KDE on purpose (to save
  power) and only switched on when needed. **VERIFIED**: rfkill
  soft-blocked, BlueDevil `bluetoothBlocked=true`.
- **VERIFIED** (source v7.2.9): `Set Powered` on a blocked adapter ends
  with `-ERFKILL`; `mgmt_errno_status()` does not know `-ERFKILL` and
  reports `Failed` (0x03) instead of `RFKILLED` (0x12).
- **VERIFIED** (btmon while bluetoothd restarts, blocked): the failing
  command is `Set Powered (0x0005)`, status `Failed (0x03)`, twice about one
  second apart; all other commands succeed. Without the block, bluetoothd
  starts without the message and switches the adapter on (live tests T1 and
  T2, `diag/2026-10-14/live-tests.md`).
- **VERIFIED** (time correlation): kded6 (BlueDevil) logs
  `PendingCall Error: "Failed"` 2 ms after the second failure; the second
  command therefore comes from a D-Bus call in kded6. The first follows
  14 ms after the management interface starts, presumably bluetoothd's
  AutoEnable (**HYPOTHESIS**, not checked in the source of bluetoothd).
- Assessment: harmless, a consequence of the maintainer's choice. No fix in the
  package: the code is in `bluetooth.ko` and bluetoothd, which the package
  does not replace.
- Side observation (**VERIFIED**): if bluetoothd is restarted while the
  adapter is on, it logs `Failed to set privacy: Rejected (0x0b)`; the
  kernel rejects Set Privacy while the controller is powered (`mgmt.c`,
  `hdev_is_powered()`). At boot the adapter is off (**HYPOTHESIS**, not
  checked).

## Journal retention

- **VERIFIED**: journald keeps only about three boots (`SystemMaxUse=50M`).
  Older findings come from saved sysinfo dumps (kernel 7.2.6): flow-ring
  timeouts and the Bluetooth error `-16` were already there.
