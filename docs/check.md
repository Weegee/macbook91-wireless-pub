# Check the state

Run the verifier without options. It needs no root:

```fish
macbook91-wireless-verify
```

Output on the test machine (kernel 7.3.3-1-cachyos, package 20261102.01-1,
2026-11-09):

```text
INFO  package 20261102.01, running kernel 7.3.3-1-cachyos
PASS  kernel series: kernel 7.3.3-1-cachyos is of Linux 7.3, a supported series (6.18 7.2 7.3)
PASS  dkms: built and installed for 7.3.3-1-cachyos
PASS  brcmfmac: patched module 20261102.01+12d3581c306b83b5 loaded
PASS  brcmfmac-wcc: patched module 20261102.01+12d3581c306b83b5 loaded
PASS  hci_uart: patched module 20261102.01+12d3581c306b83b5 loaded
PASS  brcmfmac: chip reset across system sleep on
PASS  brcmfmac: hang recovery by rebind on
PASS  brcmfmac: Wi-Fi P2P off (modprobe.d)
PASS  firmware: brcm/brcmfmac4350c2-pcie.bin present
PASS  no sleep hook unloads brcmfmac or hci_uart
PASS  WLAN: BCM4350 bound to brcmfmac, interface up
INFO  Bluetooth: hci0 present, blocked by rfkill (user setting)
PASS  journal: no WLAN/Bluetooth errors since 2026-11-08 20:31
PASS: 0 FAIL, 0 WARN
```

Each line starts with `PASS`, `WARN`, `FAIL` or `INFO`; the last line holds
the totals. Exit status 1 means a check failed, 2 invalid usage. `INFO` is a
state that is neither good nor bad, here a Bluetooth adapter the user switched
off. All options: `macbook91-wireless-verify --help`.

## Messages that are not faults

| Message | Cause |
| --- | --- |
| `bluetoothd: Failed to set mode: Failed (0x03)`, twice per boot | Bluetooth is switched off (rfkill); bluetoothd tries to power the adapter on and the kernel refuses |
| `wpa_supplicant: ... multicast RX registrations are not supported` | `brcmfmac` does not support these registrations |
| `'atop' uses wireless extensions ...` | atop uses the old interface; the driver is not affected |
| `set-wireless-regdom failed with exit code 1` | no country set, see [regdom.md](regdom.md) |
