# Live tests on the test machine, 2026-10-15

Run: live test of 2026-10-15, kernel 7.2.9-2-cachyos, package
`macbook91-wireless-dkms` 20261014.01-1 (unchanged; what is tested is a
scratch module built from the revised patches 0009 and 0010, not the installed package).
According to the maintainer, Bluetooth is switched off through KDE on purpose; the
initial state (rfkill soft-blocked, BlueDevil `bluetoothBlocked=true`) was in
place before the tests and is restored after them. Only counts are recorded,
no addresses, device names or SSIDs.

Tested: `hci_uart.ko` from a scratch build that is not part of this repository (version
`2.3+20261015.01+111f0cf7cb003721`, unsigned; `sig_enforce=N`) with the
revised patches 0009 (flag in `bcm_data`) and 0010 (speed skip only on
Macs).

## L1 Load the revised hci_uart, setup of the controller

- 10:28, `rmmod hci_uart && insmod …/hci_uart.ko`, wait 5 s until `hci0` is there.
- Result: PASS. **VERIFIED**: `rc=0`, `/sys/module/hci_uart/version` shows
  the new version, `/sys/class/bluetooth/hci0` exists. The journal from the
  load on contains 2 lines that match the setup pattern (`BCM4350C0 UART` or
  `BCM (003.001.134) build 1532`) and 0 warnings about `hci0`/`bluetooth`/`bcm`/`hci_uart`/`serial`
  (not counting the taint message).

## L2 LE scan with Bluetooth unblocked

- 10:28, `rfkill unblock bluetooth`, `bluetoothctl power on`, 30 s
  `bluetoothctl scan on`, then at once `rfkill block bluetooth`.
- Result: PASS. **VERIFIED**: `Powered: yes` 1×, 14 devices found (count
  only), `unknown advertising packet type` 0×, warnings about
  `hci0`/`bluetooth`/`bcm` in the window 0×, afterwards `Soft blocked: yes`.
- Assessment: the scan without an error message shows that `bcm_recv_event()`
  accepts advertising reports with the copied flag. It remains **NOT
  VERIFIED** whether a report with set reserved bits was among them (the
  package does not count that).

## L3 Installed module back

- 10:29, `rmmod hci_uart; modprobe hci_uart`, `rfkill block bluetooth`.
- Result: PASS. **VERIFIED**: `rc=0`, version
  `2.3+20261014.01+5b24221e8f05776a`, `modinfo -n hci_uart` →
  `updates/dkms/hci_uart.ko.zst`, `Soft blocked: yes` 1×, `bluetoothBlocked=true`
  1×, `macbook91-wireless-verify` → `PASS: 0 FAIL, 0 WARN`, journal errors since
  the test (`-p err`, hci0/bluetooth/bcm) 0.
