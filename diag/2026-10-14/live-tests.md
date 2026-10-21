# Live tests on the test machine, 2026-10-14

Run: audit run of 2026-10-14, kernel 7.2.9-2-cachyos, package
`macbook91-wireless-dkms` 20261013.01-1 (unchanged, see T3), BlueZ 5.87.
Raw data (btmon captures with the controller address) is not part of
this repository. According to the maintainer, Bluetooth is switched off through KDE on
purpose (to save power); the initial state (rfkill soft-blocked, BlueDevil
`bluetoothBlocked=true`) was in place before the tests and is restored after
them (VERIFIED: `rfkill list bluetooth` Soft blocked yes,
`bluetoothBlocked=true` unchanged).

## T1 btmon while bluetoothd starts, Bluetooth blocked

- 11:01, `btmon -w` (root) around `systemctl restart bluetooth`, evaluated
  with `btmon -r … -T`.
- Result: PASS. **VERIFIED**: exactly two MGMT commands fail, both
  `Set Powered (0x0005)` with the parameter `Powered: Enabled`, status
  `Failed (0x03)`; all other commands (Read Info, Set Privacy, Set Local
  Name, …) end with `Success (0x00)`. The journal shows two lines `Failed to
  set mode: Failed (0x03)` for them.
  ```
  11:01:07.564977 MGMT Command: Set Powered (0x0005)   Powered: Enabled
  11:01:07.565603 MGMT Event: Command Status (0x0002)   Set Powered  Status: Failed (0x03)
  11:01:08.592002 MGMT Command: Set Powered (0x0005)   Powered: Enabled
  11:01:08.592085 MGMT Event: Command Status (0x0002)   Set Powered  Status: Failed (0x03)
  ```
- **VERIFIED** (time correlation in the journal): the second command comes
  one second after the first, and `kded6` logs `PendingCall Error:
  "Failed"` 2 ms later. The caller of the second Set Powered is therefore a
  D-Bus client in kded6 (BlueDevil). The first command follows 14 ms after
  `management interface initialized`, before any D-Bus client:
  **HYPOTHESIS** that it is bluetoothd's AutoEnable (default value,
  `main.conf` without an active setting); not proven from the source of
  bluetoothd.
- Cause of the status number (source v7.2.9, earlier finding): `-ERFKILL`
  from `hci_dev_open_sync()` is not mapped in `mgmt_errno_status()` and
  therefore becomes `MGMT_STATUS_FAILED`.

## T2 Same start without the block, block restored afterwards

- 11:01, `rfkill unblock bluetooth`, `systemctl restart bluetooth`, wait 6 s.
- Result: PASS. **VERIFIED**: in the window from the restart (11:01:52) no
  line `Failed to set mode`; `btmgmt info`: `current settings: powered
  bondable ssp br/edr le secure-conn`. This confirms the hypothesis
  "consequence of the block".
- Side observation, **VERIFIED**: when the service restarts with the adapter
  on, bluetoothd logs `Failed to set privacy: Rejected (0x0b)`. The kernel
  rejects Set Privacy while the controller is powered
  (`net/bluetooth/mgmt.c:7213-7215`, `hdev_is_powered()` → `MGMT_STATUS_REJECTED`).
  This is an artefact of the restart with the adapter running; in the
  blocked state (T1) the adapter is off and Set Privacy succeeds. Not to be
  expected at boot (**HYPOTHESIS**, not checked at boot).
- 11:02 `rfkill block bluetooth`: Soft blocked yes, `bluetoothBlocked=true`
  still set (count 1).

## T3 Install and load the test package 20261014.01

- Status: BLOCKED. The agent's permission classifier refused
  `sudo -n pacman -U …/macbook91-wireless-dkms-20261014.01-1-x86_64.pkg.tar.zst`
  (reason "Blind Apply"); not circumvented. `pacman -Q` still shows
  20261013.01-1. The test package is built (`make arch-pkg-dev`, rc 0) but
  neither installed nor loaded. The module build against the 7.2.9-2
  headers ran in the scratch tree: rc 0, 5 modules,
  0 warnings (VERIFIED); the runtime behaviour of patches 0011 and 0012 is
  **NOT VERIFIED**.
- Still to be done by the maintainer: `sudo pacman -U
  dist/macbook91-wireless-dkms-20261014.01-1-x86_64.pkg.tar.zst` and
  `sudo macbook91-wireless-verify --reload`, or a release package.

## T4 One S3 cycle (SBR warning)

- Status: NOT_RUN. Reasons: suspend only with the maintainer's explicit approval
  at the moment it runs (LUKS), and asking back is not possible in this
  session; besides, T3 did not run, so the loaded module does not contain
  0011.
- State before the test, **VERIFIED**: in the boot of 2026-10-14 08:57
  there was no resume and no line `unlocked secondary bus reset` until
  11:00. The check is to be caught up at the first resume after 20261014.01
  is installed and the module reloaded (or after the next reboot):
  `journalctl -k -b | grep -c 'unlocked secondary bus reset'` should be `0`.

## T5 Regulatory domain as a no-op

- 11:04, `iw reg get` and `iw phy phy0 channels` before and after `iw reg set DE`
  (root, as `set-wireless-regdom` ran it through udev).
- Result: PASS (`REGDOM-NOOP`). **VERIFIED**: domain and channel list are
  byte-identical; DE was already set.
- **VERIFIED** (`iw reg get`): `global country DE: DFS-ETSI`; `phy#0` shows
  the driver's own domain `country 99: DFS-UNSET` (2402-2494, 5140-5360,
  5460-5860 MHz, 20 dBm), which brcmfmac gives the wiphy. The usable
  channels result from the intersection of both (`iw phy phy0 channels`: 43
  channels listed, one of them disabled (2.4 GHz channel 14), no No-IR,
  radar detection on the DFS channels).
- `/etc/conf.d/wireless-regdom` was not changed (user step).
