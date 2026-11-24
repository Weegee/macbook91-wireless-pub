# Changelog

Versions have the form YYYYMMDD.NN (release date, NN counts releases that
day); the tag is v<version>. Releases before 20261021.01 are not part of this
repository. Test evidence per version is in [test-status.json](test-status.json).

## 20261124.01 (2026-11-24)

No driver change. The report of `macbook91-wireless-verify` is coloured on a
terminal.

- `macbook91-wireless-verify`: on a terminal each row shows a symbol and the
  verdict in colour by role (green PASS, yellow WARN, red FAIL, cyan INFO),
  the check name in bold and the detail dimmed; the last line carries the
  verdict and the totals. `NO_COLOR` switches the colour off. In a pipe or a
  file the report is unchanged plain text, one `PASS`, `WARN`, `FAIL` or
  `INFO` row per check and a last line `PASS: 0 FAIL, 0 WARN`, so scripts and
  the hardware gates read it as before.
- The unpacked source tarball differs from 20261119.01 in `tools/macbook91-wireless-verify`
  and `VERSION` only; the module identities are unchanged.
- Tests: `make test` 64 ok, 0 failed. The modules were not built for this version;
  not run on the hardware.

## 20261119.01 (2026-11-19)

No driver change. The documentation is reorganised for four readers; the
package ships the shorter README.

- README: 99 lines, install and check near the top. Details moved to `docs/`:
  `install.md`, `check.md`, `configuration.md`, `kernels.md`, `regdom.md`,
  `remove.md`. The README in the package
  (`/usr/share/doc/macbook91-wireless-dkms/`) links to `docs/` only on the
  repository page.
- For developers: `docs/entwicklung/bauen.md` (build from a checkout, the
  fetcher) and `docs/entwicklung/lizenzen.md`.
- `packaging/fetch-upstream.sh`: shorter `--help` text; options and behaviour
  are unchanged.
- `make test`: the license check skips the rendered view variants in
  `docs/entwicklung/ansichten`. Result: 63 ok, 0 failed, 0 skipped.
  `namcap`: no findings for the PKGBUILD, the package has the five known
  warnings (`docs/NAMCAP.md`).
- `diff -r` of the unpacked tarballs of 20261115.01 and 20261119.01 (356
  files each) shows `README.md` and `VERSION` only; the module identities are
  unchanged. The modules were not built for this version; not run on the
  hardware.

## 20261115.01 (2026-11-15)

No driver change. The build fetches the kernel files from the GitHub mirror
gregkh/linux when git.kernel.org does not answer (GitHub Actions runners could
not reach it).

- `packaging/fetch-upstream.sh`: new option `--source auto|kernel.org|github`
  (default `auto`). Every file is still checked against `packaging/upstream.lock`,
  whichever source delivered it.
- The modules were not built for this version; not run on the hardware.

## 20261109.01 (2026-11-09)

No driver change. Documentation rewritten: numbered steps, real command output,
a check and a way back for each step.

- Fixed: `sha256sum -c --ignore-missing SHA256SUMS` skips only the `.SRCINFO`
  line on a GitHub release; the README had said three lines.
- Not built, not run on the hardware.

## 20261102.01 (2026-11-02)

No driver change. Text of the tools revised.

- `macbook91-wireless-verify` prints its last line (`FAIL: 1 FAIL, 0 WARN`)
  also when the package is not installed; the hints name a command to copy.
- `tools/dev-wlan-swap.sh` says `WLAN connected after N s`.

## 20261026.02 (2026-10-26)

No driver change. Output and help of all tools follow one form.

**Incompatible:**

- The warning of the pacman hook for an unsupported kernel is one line
  `macbook91-wireless: warning: kernel X (Linux Y) is not a kernel series macbook91-wireless supports`
  on stderr, with an indented explanation (was a `==> WARNING` block on stdout).
  Search pacman.log for `macbook91-wireless: warning:` now.
- `make` without a target lists the targets and variables (it used to install).
  `make install` is unchanged.

Other changes:

- Every tool takes `--help` and `--version`. Errors read `prog: error: text`
  on stderr; usage errors exit 2, failed runs 1.
- Not run on the hardware.

## 20261026.01 (2026-10-26)

Kernel series 7.3, the LTS kernel as the default, one patch set. The twelve
patches are unchanged.

**Incompatible:** `macbook91-wireless-verify` reports a running kernel of an
unsupported series as FAIL (was WARN) and exits 1; `patches/6.18/` and
`patches/7.2/` are replaced by one `patches/`.

- Linux 7.3 is supported next to 6.18 (LTS) and 7.2. With 7.4, 7.2 is dropped.
- One list of supported series (`/usr/lib/macbook91-wireless/kernel-series`)
  feeds DKMS, the install note, the verifier and a new pacman hook that warns
  after a kernel install for an unsupported series.
- The package depends on `linux-cachyos-lts-headers`; `linux-cachyos-headers`
  is the one optional kernel.
- Not run on the hardware.

## 20261021.01 (2026-10-21)

First release in the public repository. No driver change.

- README: installation from the release files with the checksum check, AI
  assistance note, license map.
- `LICENSES/GPL-3.0-or-later.txt` added; host names in `diag/` replaced by
  `testhost`; the Apple DSDT excerpt removed; development helpers renamed to
  `tools/dev-*.sh`. Not run on the hardware.

## 20261020.02 (2026-10-20)

Kernel 6.18 (CachyOS LTS) supported next to 7.2; the 7.2 modules are unchanged.

- New patch series `patches/6.18/`: the twelve patches rebased with line
  offsets only. The package carries one source tree per series.
- On `6.18.55-2-cachyos-lts` the verifier reports 0 FAIL, 0 WARN with WLAN up.
  Suspend/resume, Bluetooth function and the rebind recovery are not verified
  on 6.18.

## 20261020.01 (2026-10-20)

- `macbook91-wireless-verify`: the P2P check reads the last `feature_disable`
  value that modprobe.d sets and tests bit 0x10 (it misjudged `0x30` and later
  overrides).
- Own files are GPL-3.0-or-later and name their license in an SPDX line; the
  files that build the modules stay GPL-2.0-or-later.

## 20261015.01 (2026-10-15)

- Bluetooth: the LE advertising fixup takes its flag from `bcm_data`; the
  speed change to the current speed is left out on Macs only. Setup without
  warnings, LE scan without "unknown advertising packet type".
- `macbook91-wireless-verify` reads the journal from the time the modules were
  loaded.

## 20261014.01 (2026-10-14)

- WLAN: the reset on resume locks the parent bridge's config space, so the PCI
  core no longer warns `unlocked secondary bus reset`; no recovery is queued
  once module exit has begun.
- `macbook91-wireless-verify` checks `brcm/brcmfmac4350c2-pcie.bin`.
- Documentation: regulatory domain step, harmless messages.

## 20261013.01 (2026-10-13)

First release. Package `macbook91-wireless-dkms` for Linux 7.2 from kernel.org
v7.2.9 sources and ten patches:

- WLAN: reset across system sleep (`pm_reset`), recovery of a hung firmware by
  unbind, bus reset and probe (`reset_rebind`), quiet teardown, normal
  conditions of this firmware logged at debug level.
- Bluetooth: ROM firmware set up without a patch search; reserved bits of LE
  advertising event types cleared.
- Wi-Fi P2P off through modprobe.d; `macbook91-wireless-verify` with `--reload`.
- Not tested: the long mixed suspend series, Bluetooth audio and input devices
  across suspend.
