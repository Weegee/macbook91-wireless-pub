# macbook91-wireless

WLAN (Broadcom BCM4350, PCIe) and Bluetooth (BCM4350C0, UART) for the
**MacBook9,1 (A1534)** that survive suspend, recover from firmware hangs
without a reboot and keep the journal free of errors that mean nothing. A DKMS
package of patched in-tree drivers (`brcmfmac`, `hci_uart`) for Arch-family
distributions. On any other machine the modules keep the behaviour of the
upstream drivers, apart from the levels of some log messages.

<!-- Abweichung von DSP-1: the documentation is English, the project language; the rules
for German wording (Du or infinitive) do not apply, the structure rules do. -->

## Use

After the install, check the state (no root needed):

```fish
macbook91-wireless-verify
```

```text
PASS  brcmfmac: patched module 20261102.01+12d3581c306b83b5 loaded
PASS  brcmfmac: chip reset across system sleep on
PASS  WLAN: BCM4350 bound to brcmfmac, interface up
PASS: 0 FAIL, 0 WARN
```

The last line must read `PASS: 0 FAIL, 0 WARN` ([full output](docs/check.md)).

## Install

Needs a MacBook9,1 with CachyOS or another Arch-based system and the headers of
your kernel. There is no package repository and the packages are unsigned;
read the code before you build, because DKMS modules run in your kernel.

1. Download the files of the latest
   [release](https://github.com/Weegee/macbook91-wireless-pub/releases/latest)
   into an empty directory.
2. Check them and build: `sha256sum -c --ignore-missing SHA256SUMS`, then
   `makepkg -si`. The checks and a warning about `--ignore-missing` are in
   [docs/install.md](docs/install.md).
3. Load the modules (WLAN and Bluetooth drop for a few seconds):

   ```fish
   sudo macbook91-wireless-verify --reload
   ```

## What the package fixes

| Problem on the stock kernel | What the package does |
| --- | --- |
| After some suspends the WLAN firmware hangs; WLAN stays gone until a reboot | the chip is reset across system sleep (`pm_reset`) |
| A hung firmware is only reported, never recovered | unbind, reset through the PCIe bridge, probe again (`reset_rebind`, at most three times in ten minutes) |
| Hundreds of error lines while the driver tears down a dead device | silenced while the teardown is intended |
| CLM, txcap and flow-ring messages logged as errors | logged at debug level |
| Bluetooth setup searches for a patch file that does not exist and logs errors | the ROM firmware is used as macOS does |
| LE scans drop most advertisements ("unknown advertising packet type") | reserved bits of the event types are cleared |
| `p2p-dev-wlan0` errors on every connect and resume | Wi-Fi P2P is turned off in modprobe.d |

Patches: `patches/`. Measurements: [docs/FINDINGS.md](docs/FINDINGS.md).

## Read on

| Task | Page |
| --- | --- |
| Install in full | [docs/install.md](docs/install.md) |
| Check the state, harmless messages | [docs/check.md](docs/check.md) |
| Set the regulatory domain | [docs/regdom.md](docs/regdom.md) |
| Change a module parameter | [docs/configuration.md](docs/configuration.md) |
| Kernel series and firmware | [docs/kernels.md](docs/kernels.md) |
| Remove the package | [docs/remove.md](docs/remove.md) |
| Changes per version, test results | [docs/CHANGELOG.md](docs/CHANGELOG.md), [docs/test-status.json](docs/test-status.json) |
| Build from a checkout, targets, fetcher | [docs/entwicklung/bauen.md](docs/entwicklung/bauen.md) |
| Licenses by path | [docs/entwicklung/lizenzen.md](docs/entwicklung/lizenzen.md) |

## Bug reports

Use the [issue tracker](https://github.com/Weegee/macbook91-wireless-pub/issues).
Name the kernel (`uname -r`), the package version and the output of
`macbook91-wireless-verify`.

## AI assistance

Claude (an AI model by Anthropic) wrote the project's code, tests and
documentation; the maintainer gave the directions and made the decisions.
Hardware checks ran on a MacBook9,1 under the maintainer's direction and count
only as far as `docs/test-status.json` records them as run. Commits Claude
contributed to carry a Co-Authored-By trailer; the patch files in `patches/` do
not. Read the code before you load a kernel module or run a script as root.

## License

GPL-3.0-or-later ([LICENSE](LICENSE)) for the project's own files; the files
that build the modules are GPL-2.0-or-later, kernel files keep their licenses.
Per path: [docs/entwicklung/lizenzen.md](docs/entwicklung/lizenzen.md).

See also: [macbook91-hw-fixes](https://github.com/Weegee/macbook91-hw-fixes-pub),
[macbook91-cs4208-dkms](https://github.com/Weegee/macbook91-cs4208-pub),
[macbook91-facetimehd-dkms](https://github.com/Weegee/macbook91-facetimehd-pub).
