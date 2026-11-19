# Licenses by path

Every own file with comment syntax names its license in an
`SPDX-License-Identifier` line; `tests/run-tests.sh` checks it. GPLv2 requires
whoever passes on a built module to pass the files that build it on under GPLv2
too, hence the split.

| License | Paths |
| --- | --- |
| GPL-3.0-or-later ([LICENSE](../../LICENSE)) | `tools/`, `tests/run-tests.sh`, `packaging/` (except `overlay/`), `Makefile`, `VERSION`, `.gitignore`, `src/macbook91-wireless/modprobe.d/`, the documentation (`*.md`, `docs/`) |
| GPL-2.0-or-later | `src/macbook91-wireless/Makefile`, `src/macbook91-wireless/dkms.conf`, `packaging/overlay/brcm80211.Kbuild`, `tests/test_le_adv_fixup.c` (compiled with code from `hci_bcm.c`) |
| GPL-2.0-only | `packaging/overlay/bluetooth.Kbuild` (its `hci_uart` object list is the kernel's) |
| ISC | the kernel files under `brcm80211/` (`brcmfmac`), [LICENSES/ISC](../../LICENSES/ISC) (Broadcom text) |
| GPL-2.0-or-later, except below | the kernel files under `drivers/bluetooth/` (`hci_uart`); `hci_ll.c`, `hci_qca.c`, `btqca.h` are GPL-2.0-only, `hci_aml.c` GPL-2.0-only OR MIT ([LICENSES/MIT](../../LICENSES/MIT), Copyright (C) 2024 Amlogic, Inc.) |
| per file changed | `patches/`: ISC for `brcmfmac`, GPL-2.0-or-later for `hci_ldisc.c` (0001) and `hci_bcm.c` (0009, 0010) |
| none stated | `diag/` (output recorded on the test machine, host name replaced by `testhost`); `release/<version>/` carries the licenses stated in it |

The two functional lines of `brcm80211.Kbuild` follow the kernel's ISC-licensed
`drivers/net/wireless/broadcom/brcm80211/Makefile` (Copyright (c) 2010 Broadcom
Corporation). The kernel files are fetched by `make dist` into
`src/macbook91-wireless/series/<S>/kernel/` and shipped in the source tarball and
in `/usr/src`. No Apple binaries or Apple code are included. The package
installs the ISC and MIT texts to `/usr/share/licenses/macbook91-wireless-dkms/`;
the source tarball does not contain `LICENSES/GPL-3.0-or-later.txt` (it carries
`LICENSE`).
