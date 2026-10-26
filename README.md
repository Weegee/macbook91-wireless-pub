# macbook91-wireless

WLAN (Broadcom BCM4350, PCIe) and Bluetooth (BCM4350C0, UART) for the
**MacBook9,1 (A1534)** that survive suspend, recover from firmware hangs
without a reboot and keep the journal free of errors that mean nothing. It is
a DKMS package of patched in-tree drivers, `brcmfmac` and `hci_uart`, for
Arch-family distributions.

This README is also part of the source tarball and is installed to
`/usr/share/doc/macbook91-wireless-dkms/`. Its relative links work on the
repository page. In an unpacked tarball the links to `docs/` and `diag/` are
dead, because those directories exist only in the Git repository, while those
to `LICENSE` and `LICENSES/` resolve. On an installed system all of them are
dead; the package installs the ISC and MIT texts to
`/usr/share/licenses/macbook91-wireless-dkms/`.

## AI assistance

This project was written by Claude (an AI model by Anthropic): Claude wrote the
project's own code, tests and documentation, and the maintainer gave the directions
and made the decisions. Hardware checks were run on a MacBook9,1 under the
maintainer's direction and count only as far as docs/test-status.json records them as
run; everything else there is marked as not run or carried over. Commits that Claude
contributed to carry a Co-Authored-By trailer; the first public commit is a snapshot
of the earlier private history and carries it too. Read the code before you load a
kernel module or run a script as root.

The patch files in `patches/` are mail-format kernel patches: their From line names the
maintainer and they carry no trailer.

## What it fixes

| Problem on the stock kernel | What the package does |
| --- | --- |
| After some suspends the WLAN firmware hangs (D3 handshake, then timeouts); WLAN stays gone until a reboot | `brcmfmac` removes the device state before system sleep and probes a freshly reset chip after resume (`pm_reset`) |
| A hung firmware is only reported, never recovered | Two command timeouts in a row, or the driver's own reset request, unbind the device, reset it through the PCIe bridge and probe it again (`reset_rebind`, at most three times in ten minutes) |
| Hundreds of error lines while the driver tears down a dead device | silenced while the teardown is intended |
| CLM, txcap and flow-ring messages logged as errors although they are normal for this firmware | logged at debug level |
| Bluetooth setup searches for a patch file that does not exist for this chip and logs errors; a refused speed change logs two more | the ROM firmware is used as macOS does: no search, no redundant speed change, no warnings about the Mac's ACPI layout |
| LE scans drop most advertisements of nearby devices ("unknown advertising packet type") | reserved bits of the controller's event types are cleared, as the specification requires of receivers |
| `p2p-dev-wlan0` errors on every connect and resume | Wi-Fi P2P is turned off in `/usr/lib/modprobe.d/macbook91-wireless.conf` (override described there) |

Measurements and their status (verified, not verified, hypothesis) are in
[docs/FINDINGS.md](docs/FINDINGS.md).

Every patch is in `patches/`, one set for every kernel series, and is written
to be reviewable on its own. The modules activate their Mac-specific behaviour only where the kernel
already detects an Apple machine (`hci_bcm`) or only on the PCIe path of
`brcmfmac`; every other machine running these modules keeps upstream
behaviour, except for the message levels.

## Install

There is no package repository. The packages are unsigned, and DKMS compiles
kernel modules that are loaded into your running kernel: read the code first.

From the files of a release (the newest directory under `release/`): put
`PKGBUILD`, `macbook91-wireless.install`,
`macbook91-wireless-dkms-<version>.tar` and `SHA256SUMS` into one empty
directory. `makepkg` needs `base-devel`; `-s` installs the dependencies and
`-i` installs the built package with `pacman -U`. The PKGBUILD also pins the
SHA-256 of the tarball, and `makepkg` checks it.

```fish
sha256sum -c --ignore-missing SHA256SUMS
makepkg -si
sudo macbook91-wireless-verify --reload   # or reboot
macbook91-wireless-verify
```

`--ignore-missing` skips every line of `SHA256SUMS` whose file is not in the
directory (`.SRCINFO`, `STATUS.txt`, `upstream.lock`), so the command also
exits successfully when only some of the files were downloaded. The check
counts only if it prints `OK` for these three: `PKGBUILD`,
`macbook91-wireless.install` and `macbook91-wireless-dkms-<version>.tar`. Look
for the three `OK` lines, not only for the exit status; a `FAILED` means: do
not build.

From a git checkout of this repository (`make dist` builds the tarball from
the files Git tracks, so a source tarball or a zip download is not enough;
clean working tree, network access to git.kernel.org for the kernel files):

```fish
make arch-pkg
sudo pacman -U dist/macbook91-wireless-dkms-*.pkg.tar.zst
sudo macbook91-wireless-verify --reload   # or reboot
```

DKMS builds the modules for every installed kernel of a series the package
supports and needs that kernel's headers. The list is
`/usr/src/macbook91-wireless-*/KERNEL-SERIES`, written from
`packaging/upstream.lock`; `/usr/lib/macbook91-wireless/kernel-series --list`
prints it. The CachyOS LTS kernel is the default: its series is always
supported, and the package depends on `linux-cachyos-lts-headers` (gcc). The
current CachyOS series is supported as well; for it install
`linux-cachyos-headers`, which brings the clang, lld and llvm its clang-built
kernel needs. A kernel of any other series keeps its stock drivers: DKMS
skips it, a pacman hook prints a warning (`macbook91-wireless: warning: kernel
... is not a kernel series macbook91-wireless supports`) for it after every
transaction that installs a kernel, and `macbook91-wireless-verify` reports a
FAIL on it.

| Series | Kernel (tested) | Status |
| --- | --- | --- |
| 7.3 | `7.3.0-4-cachyos` (clang) | release 20261026.01: all five modules build (vermagic `7.3.0-4-cachyos`); not run on the MacBook9,1 (NOT VERIFIED), see [docs/test-status.json](docs/test-status.json) |
| 7.2 | `7.2.11-1-cachyos` (clang) | run on the MacBook9,1 up to release 20261015.01; later releases carry that result over, see [docs/test-status.json](docs/test-status.json) |
| 6.18 | `6.18.55-2-cachyos-lts` (gcc) | run on the MacBook9,1 with release 20261020.02: `macbook91-wireless-verify` 0 FAIL, 0 WARN, WLAN up (VERIFIED); suspend/resume, Bluetooth function and the rebind recovery NOT VERIFIED on 6.18, see [docs/test-status.json](docs/test-status.json) |

Releases before 20261021.01 are not part of this repository; the table and
`docs/test-status.json` keep the results of their hardware runs as history.

**Rollback:** `sudo pacman -R macbook91-wireless-dkms`, then reboot or reload
`brcmfmac` and `hci_uart`. Nothing outside the package's own files is changed.

## Module parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `brcmfmac pm_reset` | `1` | reset the chip across system sleep instead of the firmware's D3 path; no Wake-on-WLAN while on |
| `brcmfmac reset_rebind` | `1` | recover a hung firmware by unbind, bus reset and probe |
| `brcmfmac feature_disable` | `0x10` (modprobe.d) | `0x10` turns off Wi-Fi P2P; `0` brings it back |
| `hci_uart apple_patchram` | `0` | look for a Bluetooth patch file on Macs anyway |

## Firmware

There is no separate firmware package, deliberately. The WLAN firmware is
`brcm/brcmfmac4350c2-pcie.bin` from `linux-firmware-broadcom`, the only FullMAC
firmware for this chip. The firmware in macOS and in Boot Camp for this
machine is the BMAC (SoftMAC) variant, which `brcmfmac` cannot run. The
Bluetooth controller runs on its ROM: neither macOS 12 nor Boot Camp ships a
patch for the BCM4350C0. Details are in [docs/FINDINGS.md](docs/FINDINGS.md).

## Regulatory domain (user step)

The package cannot set it: `/usr/bin/set-wireless-regdom` from
`wireless-regdb` reads only `/etc/conf.d/wireless-regdom`, a file of that
package. Until a country is set there, udev logs `cfg80211: Process
'/usr/bin/set-wireless-regdom' failed with exit code 1` once per boot. On
CachyOS, `cachyos-iw-set-regdomain.service` already sets the domain from the
time zone, so the step removes that message and applies the country from
the start. For Germany:

```fish
sudo sed -i 's/^#WIRELESS_REGDOM="DE"/WIRELESS_REGDOM="DE"/' /etc/conf.d/wireless-regdom
```

`brcmfmac` does not pass the country to the BCM4350 firmware on x86;
cfg80211 limits the channels instead (docs/FINDINGS.md, "Regulatory domain").

## Messages that are not faults

| Message | Cause |
| --- | --- |
| `bluetoothd: Failed to set mode: Failed (0x03)`, twice per boot | Bluetooth is switched off (rfkill); bluetoothd tries to power the adapter on and the kernel refuses |
| `wpa_supplicant: ... multicast RX registrations are not supported` | `brcmfmac` does not support these registrations |
| `'atop' uses wireless extensions ...` | atop uses the old interface; the driver is not affected |
| `set-wireless-regdom failed with exit code 1` | no country in `/etc/conf.d/wireless-regdom` (see above) |

## Build from source

```fish
make dist           # fetch the kernel files at the locked tag, write dist/*.tar (git checkout)
make arch-pkg-dev   # build the package from the working tree
make test           # hermetic tests
make                # without a target: lists the targets and variables
```

Every script and tool answers `--help` (usage, examples, options, exit status)
and `--version`; invalid usage ends with status 2 and an `error:` line on
stderr. Messages go to stderr, results to stdout. The shared helpers of the
packaging and development scripts are in `packaging/lib.sh`.

`packaging/fetch-upstream.sh` fetches the kernel files listed in
`packaging/files.list` from the stable tree on git.kernel.org, checks each one
against `packaging/upstream.lock`, applies `patches/` and adds two Kbuild
files, once per kernel series: the result is one self-contained tree
`series/<S>/` in the module directory, and the module Makefile builds the one
that matches the target kernel (`UTS_RELEASE`). The one patch set applies to
every series with `patch -F0` (line offsets, no fuzz). A new kernel series
needs lockfile entries (`--accept-new`) and must take the same set; where it
does not, the set is reworked so that it fits every series, never split per
series. A new stable tag of a series that is already shipped is a lockfile
update and changes only that series' module ID.

## License

This project's own files are GPL-3.0-or-later ([LICENSE](LICENSE)), except
the files that build the modules: GPLv2 requires whoever passes on a built
module to pass those on under GPLv2 too, so they are GPL-2.0-or-later. Every
own file with comment syntax names its license in an
`SPDX-License-Identifier` line. Files from the kernel, and the patches to
them, keep the license of the kernel file. The other license texts are in
[LICENSES/](LICENSES).

- **GPL-3.0-or-later:** `tools/`, `tests/run-tests.sh`, `packaging/` (except
  `overlay/`), `Makefile`, `VERSION`, `.gitignore`,
  `src/macbook91-wireless/modprobe.d/` and `src/macbook91-wireless/.gitignore`,
  and the documentation and records (`*.md`, `docs/`). The text is in
  [LICENSE](LICENSE); the Git repository also keeps it under its SPDX name,
  `LICENSES/GPL-3.0-or-later.txt`, which the source tarball does not contain.
- **GPL-2.0-or-later:** the files that build the modules,
  `src/macbook91-wireless/Makefile`, `src/macbook91-wireless/dkms.conf` and
  `packaging/overlay/brcm80211.Kbuild`; `tests/test_le_adv_fixup.c`, which is
  compiled with code from `hci_bcm.c`. The two functional lines of
  `brcm80211.Kbuild` (the `subdir-ccflags` line for `CONFIG_BRCMDBG` and the
  `obj-$(CONFIG_BRCMFMAC)` line) follow the kernel's ISC-licensed
  `drivers/net/wireless/broadcom/brcm80211/Makefile`, Copyright (c) 2010
  Broadcom Corporation.
- **GPL-2.0-only:** `packaging/overlay/bluetooth.Kbuild`, which builds a
  module as well; its `hci_uart` object list is that of the kernel's
  `drivers/bluetooth/Makefile`.
- **Kernel files**, fetched by `make dist` into
  `src/macbook91-wireless/series/<S>/kernel/` and shipped in the source tarball and in
  `/usr/src`: the files under `brcm80211/` (`brcmfmac`) are ISC; the files
  under `drivers/bluetooth/` (`hci_uart`) are GPL-2.0-or-later except
  `hci_ll.c`, `hci_qca.c` and `btqca.h` (GPL-2.0-only) and `hci_aml.c`
  (GPL-2.0-only OR MIT). The two `Kbuild` files there are copies of
  `packaging/overlay/`. [LICENSES/ISC](LICENSES/ISC) is the Broadcom ISC text;
  [LICENSES/MIT](LICENSES/MIT) is the MIT text of `hci_aml.c`
  (Copyright (C) 2024 Amlogic, Inc.). Nothing else in this repository is MIT.
- **`patches/`:** each hunk has the license of the file it changes:
  ISC for `brcmfmac`, GPL-2.0-or-later for `hci_ldisc.c` (0001) and
  `hci_bcm.c` (0009, 0010).
- **No license stated here:** `diag/` (command output recorded on the test
  machine; the host name is replaced by `testhost`, see
  [diag/README.md](diag/README.md)). No Apple binaries or Apple code are
  included. `release/<version>/` holds the
  files of that release under the licenses stated in it.
