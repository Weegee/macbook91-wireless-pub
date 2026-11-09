# macbook91-wireless

WLAN (Broadcom BCM4350, PCIe) and Bluetooth (BCM4350C0, UART) for the
**MacBook9,1 (A1534)** that survive suspend, recover from firmware hangs
without a reboot and keep the journal free of errors that mean nothing. It is
a DKMS package of patched in-tree drivers, `brcmfmac` and `hci_uart`, for
Arch-family distributions. On any other machine the modules keep the behaviour
of the upstream drivers, apart from the levels of some log messages.

<!-- Abweichung von DSP-1: the documentation is English, the project language; the rules
for German wording (Du or infinitive) do not apply, the structure rules do. -->

## What the package fixes

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
to be reviewable on its own. The modules activate their Mac-specific behaviour
where the kernel already detects an Apple machine (`hci_bcm`) or on the PCIe
path of `brcmfmac`; every other machine running these modules keeps upstream
behaviour, except for the message levels.

## Installation

Install the package from the files of a release, or build it from a checkout of
the repository. Both ways end with a reload of the modules and a check.
[Verification status](#verification-status) lists which commands were run.

There is no package repository and the packages are unsigned. DKMS compiles
kernel modules that are loaded into your running kernel, so read the code before
you build.

### Prerequisites

- A MacBook9,1 with CachyOS or another Arch-based system.
- The package `base-devel` (for `makepkg`). The package itself needs `dkms`,
  `linux-firmware-broadcom` and `linux-cachyos-lts-headers`; `makepkg -s` and
  `pacman` install them.
- The headers of every kernel you want the modules for (see
  [Kernel series](#kernel-series)).
- For the checkout route: a git checkout of the repository, because
  `make dist` builds the tarball from the files Git tracks (a source tarball or
  a zip download is not enough), a clean working tree and network access to
  git.kernel.org for the kernel files.

### Install from the release files

1. Download all files of the latest
   [release](https://github.com/Weegee/macbook91-wireless-pub/releases/latest)
   into one empty directory. `makepkg` needs `PKGBUILD`,
   `macbook91-wireless.install` and the source tarball
   `macbook91-wireless-dkms-VERSION.tar`, where VERSION is the version of the
   release. `SHA256SUMS` lists the files to check.

   > **Warning:** `--ignore-missing` skips every line of `SHA256SUMS` whose
   > file is not in the directory, so step 2 can exit successfully while the
   > install file or the tarball is missing. GitHub serves `.SRCINFO` as
   > `default.SRCINFO`, so that line is always skipped. A missing or changed
   > file ends up in a package that runs as root. Run step 3 only when
   > `PKGBUILD`, `macbook91-wireless.install` and the tarball all read `OK`.

2. In that directory, check the files:

   ```fish
   sha256sum -c --ignore-missing SHA256SUMS
   ```

   Output for release 20261102.01 (the five files that are present; the
   `.SRCINFO` line is skipped):

   ```text
   PKGBUILD: OK
   macbook91-wireless.install: OK
   upstream.lock: OK
   STATUS.txt: OK
   macbook91-wireless-dkms-20261102.01.tar: OK
   ```

   A `FAILED` line means: do not build.

3. Build the package and install it with `pacman -U`. The PKGBUILD pins the
   SHA-256 of the tarball, and `makepkg` checks it again:

   ```fish
   makepkg -si
   ```

   DKMS builds the modules for every installed kernel of a supported series.

4. Load the installed modules. WLAN and Bluetooth drop for a few seconds; a reboot
   does the same:

   ```fish
   sudo macbook91-wireless-verify --reload
   ```

5. Check the result:

   ```fish
   macbook91-wireless-verify
   ```

   The last line must read `PASS: 0 FAIL, 0 WARN` (see
   [Check the state](#check-the-state)).

To go back, see [Roll back and remove](#roll-back-and-remove).

### Build from a checkout

1. Clone the repository and change into it:

   ```fish
   git clone https://github.com/Weegee/macbook91-wireless-pub.git
   cd macbook91-wireless-pub
   ```

2. Build the package. `make` fetches the kernel files from git.kernel.org
   and checks each against `packaging/upstream.lock`:

   ```fish
   make arch-pkg
   ```

   `make arch-pkg` refuses a tree whose tarball is not the one the PKGBUILD
   pins. On a tree between two releases use `make arch-pkg-dev`.

3. Install the package:

   ```fish
   sudo pacman -U dist/macbook91-wireless-dkms-*.pkg.tar.zst
   ```

4. Load the installed modules and check them as in steps 4 and 5 of the first route.

## Usage

### Check the state

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

Each check prints one line that starts with `PASS`, `WARN`, `FAIL` or `INFO`;
the last line holds the totals. The exit status is 1 when a check failed,
2 for invalid usage. `INFO` lines report a state that is neither good nor bad,
here a Bluetooth adapter that the user switched off.

### Set the regulatory domain (optional)

The package cannot set the country: `/usr/bin/set-wireless-regdom` from
`wireless-regdb` reads only `/etc/conf.d/wireless-regdom`, a file of that
package. Until a country is set there, udev logs `cfg80211: Process
'/usr/bin/set-wireless-regdom' failed with exit code 1` once per boot. On
CachyOS, `cachyos-iw-set-regdomain.service` already sets the domain from the
time zone, so this step removes that message and applies the country from the
start.

1. Enable the country in `/etc/conf.d/wireless-regdom`. This example is for
   Germany; for another country replace `DE` in both places with its
   two-letter code:

   ```fish
   sudo sed -i 's/^#WIRELESS_REGDOM="DE"/WIRELESS_REGDOM="DE"/' /etc/conf.d/wireless-regdom
   ```

2. Check the file:

   ```fish
   grep '^WIRELESS_REGDOM' /etc/conf.d/wireless-regdom
   ```

   Expected output:

   ```text
   WIRELESS_REGDOM="DE"
   ```

To go back, comment the line out again:

```fish
sudo sed -i 's/^WIRELESS_REGDOM="DE"/#WIRELESS_REGDOM="DE"/' /etc/conf.d/wireless-regdom
```

`brcmfmac` does not pass the country to the BCM4350 firmware on x86; cfg80211
limits the channels instead (see
[docs/FINDINGS.md, Regulatory domain](docs/FINDINGS.md#regulatory-domain)).

### Messages that are not faults

These lines appear in the journal and do not point to a defect:

| Message | Cause |
| --- | --- |
| `bluetoothd: Failed to set mode: Failed (0x03)`, twice per boot | Bluetooth is switched off (rfkill); bluetoothd tries to power the adapter on and the kernel refuses |
| `wpa_supplicant: ... multicast RX registrations are not supported` | `brcmfmac` does not support these registrations |
| `'atop' uses wireless extensions ...` | atop uses the old interface; the driver is not affected |
| `set-wireless-regdom failed with exit code 1` | no country in `/etc/conf.d/wireless-regdom` (see [Set the regulatory domain](#set-the-regulatory-domain-optional)) |

### Roll back and remove

1. Remove the package. DKMS removes the modules with it, and nothing outside
   the package's own files is changed:

   ```fish
   sudo pacman -R macbook91-wireless-dkms
   ```

2. Reboot, or unload and load `brcmfmac` and `hci_uart` again, so that the
   drivers of the kernel come back.

3. Check that the module no longer comes from DKMS:

   ```fish
   modinfo -F filename brcmfmac
   ```

   The path must not contain `updates/dkms`. With the package installed it
   reads `/lib/modules/7.3.3-1-cachyos/updates/dkms/brcmfmac.ko.zst`.

## Kernel series

DKMS builds the modules for every installed kernel of a series the package
supports and needs that kernel's headers. The list is
`/usr/src/macbook91-wireless-*/KERNEL-SERIES`, written from
`packaging/upstream.lock`. Print it:

```fish
/usr/lib/macbook91-wireless/kernel-series --list
```

Output on the test machine, 2026-11-09:

```text
6.18 7.2 7.3
```

The CachyOS LTS kernel is the default: its series is always supported, and the
package depends on `linux-cachyos-lts-headers` (gcc). The current CachyOS
series is supported as well; for it install `linux-cachyos-headers`, which
brings the clang, lld and llvm its clang-built kernel needs. A kernel of any
other series keeps its stock drivers: DKMS skips it, a pacman hook prints a
warning (`macbook91-wireless: warning: kernel ... is not a kernel series
macbook91-wireless supports`) for it after every transaction that installs a
kernel, and `macbook91-wireless-verify` reports a FAIL on it.

| Series | Kernel (tested) | Status |
| --- | --- | --- |
| 7.3 | `7.3.0-4-cachyos` (clang) | release 20261026.01: all five modules build (vermagic `7.3.0-4-cachyos`); `macbook91-wireless-verify` of release 20261102.01 on `7.3.3-1-cachyos` on the MacBook9,1 on 2026-11-09: 0 FAIL, 0 WARN, WLAN up (VERIFIED, read-only check); suspend/resume, Bluetooth function and the rebind recovery NOT VERIFIED on 7.3, see [docs/test-status.json](docs/test-status.json) |
| 7.2 | `7.2.11-1-cachyos` (clang) | run on the MacBook9,1 up to release 20261015.01; later releases carry that result over, see [docs/test-status.json](docs/test-status.json) |
| 6.18 | `6.18.55-2-cachyos-lts` (gcc) | run on the MacBook9,1 with release 20261020.02: `macbook91-wireless-verify` 0 FAIL, 0 WARN, WLAN up (VERIFIED); suspend/resume, Bluetooth function and the rebind recovery NOT VERIFIED on 6.18, see [docs/test-status.json](docs/test-status.json) |

Releases before 20261021.01 are not part of this repository; the table and
`docs/test-status.json` keep the results of their hardware runs as history.

## Firmware

There is no separate firmware package, deliberately. The WLAN firmware is
`brcm/brcmfmac4350c2-pcie.bin` from `linux-firmware-broadcom`, the only FullMAC
firmware for this chip. The firmware in macOS and in Boot Camp for this
machine is the BMAC (SoftMAC) variant, which `brcmfmac` cannot run. The
Bluetooth controller runs on its ROM: neither macOS 12 nor Boot Camp ships a
patch for the BCM4350C0. Details are in
[docs/FINDINGS.md, Firmware](docs/FINDINGS.md#firmware).

## Verification status

VERIFIED on the test machine on 2026-11-09 with package 20261102.01-1 on kernel
7.3.3-1-cachyos: `macbook91-wireless-verify` (output under
[Check the state](#check-the-state)),
`/usr/lib/macbook91-wireless/kernel-series --list`, `modinfo -F filename brcmfmac`,
`sha256sum -c --ignore-missing SHA256SUMS` on the files of the public release
20261102.01, `git clone` and `make arch-pkg` in a fresh clone of the public repository
(`make arch-pkg` took about one minute and built the package, with the tarball the
PKGBUILD pins), and the substitution of the `sed` command under
[Set the regulatory domain](#set-the-regulatory-domain-optional) on the output
of `/etc/conf.d/wireless-regdom` (it matches one line; the file was not written).

NOT VERIFIED for this version: every command that needs root or changes the
system (`makepkg -si`, `sudo pacman -U` of the package built by `make arch-pkg`,
`sudo macbook91-wireless-verify --reload`, both `sed -i` commands, `sudo pacman -R`)
and the removal check after it. Earlier runs, per kernel series, are in the table under
[Kernel series](#kernel-series) and in `docs/test-status.json`.

## Configuration

The package installs `/usr/lib/modprobe.d/macbook91-wireless.conf`, which sets
`feature_disable`. Its comments describe how to override it. The other
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
(see `man modprobe.d`), then reload the modules or reboot. That step was not run
for `pm_reset` or `reset_rebind` (NOT VERIFIED).

## Development

These targets run in a git checkout:

- `make dist` fetches the kernel files at the locked tag and writes
  `dist/*.tar`.
- `make arch-pkg-dev` builds the package from the working tree.
- `make test` runs the hermetic tests (no hardware, no root).
- `make` without a target lists the targets and variables.

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
every series with `patch -F0` (line offsets, no fuzz). A further kernel series
needs lockfile entries (`--accept-new`) and must take the same set; where it
does not, the set is reworked so that it fits every series, never split per
series. A later stable tag of a series that is already shipped is a lockfile
update and changes only that series' module ID.

## Documentation

- [docs/FINDINGS.md](docs/FINDINGS.md): measurements and their status.
- [docs/CHANGELOG.md](docs/CHANGELOG.md): what changed in each version.
- [docs/test-status.json](docs/test-status.json): every test run with its
  result and the open hardware gates.
- [docs/NAMCAP.md](docs/NAMCAP.md): the `namcap` findings of the package and
  why they stay.
- [DIAGNOSIS.md](DIAGNOSIS.md) and [diag/README.md](diag/README.md): the
  diagnosis of the suspend failure and the recorded command output behind it.
- [STRUCTURE.md](STRUCTURE.md): the rules for the layout of the repository.
- `macbook91-wireless-verify --help` and `/usr/lib/macbook91-wireless/kernel-series --help`:
  the options of the tools.

This README is part of the source tarball and is installed to
`/usr/share/doc/macbook91-wireless-dkms/`. Its relative links work on the
repository page. In an unpacked tarball the links to `docs/` and `diag/` are
dead, because those directories exist only in the Git repository, while those
to `LICENSE` and `LICENSES/` resolve. On an installed system all of them are
dead; the package installs the ISC and MIT texts to
`/usr/share/licenses/macbook91-wireless-dkms/`.

## Bug reports

Report bugs in the [issue tracker](https://github.com/Weegee/macbook91-wireless-pub/issues)
of the public repository. Name the kernel (`uname -r`), the package version and
the output of `macbook91-wireless-verify`.

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

## See also

- [macbook91-hw-fixes](https://github.com/Weegee/macbook91-hw-fixes-pub): the other
  hardware fixes for the MacBook9,1 (NVMe and lid wake, brightness, charge limit, keyboard,
  hibernate).
- [macbook91-cs4208-dkms](https://github.com/Weegee/macbook91-cs4208-pub): the audio driver
  for the MacBook9,1.
- [macbook91-facetimehd-dkms](https://github.com/Weegee/macbook91-facetimehd-pub): the camera
  driver.
