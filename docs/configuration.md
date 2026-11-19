# Change a module parameter

The package installs `/usr/lib/modprobe.d/macbook91-wireless.conf`, which sets
`feature_disable`; its comments describe how to override it. The other
parameters keep their defaults:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `brcmfmac pm_reset` | `1` | reset the chip across system sleep instead of the firmware's D3 path; no Wake-on-WLAN while on |
| `brcmfmac reset_rebind` | `1` | recover a hung firmware by unbind, bus reset and probe |
| `brcmfmac feature_disable` | `0x10` (modprobe.d) | `0x10` turns off Wi-Fi P2P; `0` brings it back |
| `hci_uart apple_patchram` | `0` | look for a Bluetooth patch file on Macs anyway |

Read the value of a parameter of the loaded module:

```fish
cat /sys/module/brcmfmac/parameters/pm_reset
```

Output on the test machine, 2026-11-09:

```text
Y
```

Set a parameter with an `options` line in a file under `/etc/modprobe.d/`
(`man modprobe.d`), then reload the modules or reboot. Not checked: that step
for `pm_reset` and `reset_rebind`.
