# Changelog

Versions have the form YYYYMMDD.NN (release date, NN counts releases that
day). The release tag is v<version>. Releases before 20261021.01 are not part
of this repository; their entries below are kept as history.

## 20261021.01

**First release in the public repository: documentation, licensing and
attribution only. No driver change.** Patches, kernel sources, Kbuild files,
the module Makefile, `dkms.conf` and `macbook91-wireless-verify` are the
same as in 20261020.02 (module payload compared, see below). The source
identities are unchanged, `494451d9a8ce5f25` for 7.2 and `2eed8ec6343efe4f`
for 6.18; the modules report them as `20261021.01+<id>`.

Commit hashes named in entries up to 20261021.01 belong to the maintainer's private history and do not exist in the public repository.

- README: AI assistance note (what Claude wrote, how hardware checks
  count, the Co-Authored-By trailer on commits and on the first public
  snapshot); installation from the release files, with the checksum check
  spelled out (`sha256sum -c --ignore-missing` must print OK for the
  PKGBUILD, the `.install` file and the tarball) or `make dist &&
  make arch-pkg` from a git checkout; the license section maps the public
  paths; the provenance of the ISC-licensed `brcm80211.Kbuild` is stated;
  a note says where the relative links work: all of them in the Git
  repository, `LICENSE` and `LICENSES/` also in an unpacked tarball, none
  in the installed README (`docs/` and `diag/` exist only in the Git
  repository).
- `LICENSES/GPL-3.0-or-later.txt` added (the text of `LICENSE`). The source
  tarball carries `LICENSE` only, and the README says so.
- `STRUCTURE.md` no longer says that logs are never tracked (redacted logs
  are, in `diag/`) and lists the SPDX copy of the license.
- `packaging/arch/PKGBUILD` and `.SRCINFO`: `url` is the public repository.
- `diag/`: the host name in the two raw logs is replaced by `testhost` (the
  host field is the only change, line counts are equal); `diag/README.md`
  added; the wording of the two live-test reports, `DIAGNOSIS.md` and the
  files in `docs/` is neutral.
- Development helpers renamed to `tools/dev-suspend-cycle.sh` and
  `tools/dev-wlan-swap.sh` (not packaged); the test globs follow.
- `.gitignore` names build and test output only.
- Texts that mentioned earlier releases or project-internal notes now say
  that these are not part of this repository (README, `docs/test-status.json`,
  the live-test reports, the 20261020.01 entry below);
  `packaging/promote-release.sh` makes no claim about Git history.
- The decompiled DSDT excerpt (Apple's code) is no longer part of the
  repository; `diag/README.md` describes in this project's words what it
  showed (ARPT under RP09, CMPE under RP10).
  The 2026-10-15 live-test report no longer cites a scratch directory. The
  README says that commits carry the trailer and that the patch files do
  not.
- `release/` holds the current release only; older release directories are
  no longer part of the tree.
- Module payload compared with the 20261020.02 tarball (`diff -r` of the
  unpacked tarballs, 241 files each): only `README.md` and `VERSION`
  differ. Kernel sources, patches, Kbuild files, `KERNEL-SERIES`, the module
  Makefile, `dkms.conf`, `modprobe.d`, the verify tool, the install
  Makefile and the license texts are byte for byte the same.
- Modules built unprivileged from the 20261020.02 tarball and from the
  20261021.01 tarball at the same path, for `7.2.11-1-cachyos` (clang) and
  `6.18.55-2-cachyos-lts` (gcc). Built with the same package version
  (`PKGVER=20261021.01` for both), all five `.ko` files (`brcmfmac`,
  `brcmfmac-wcc`, `brcmfmac-cyw`, `brcmfmac-bca`, `hci_uart`) are byte for
  byte the same. Built with each tarball's own version they differ in the
  version string only (`srcversion` is the same): the module ID is the
  package version plus the source part, and the source part is the same
  (`494451d9a8ce5f25` on 7.2, `2eed8ec6343efe4f` on 6.18). This is a build
  comparison, not a hardware check.
- NOT RUN for 20261021.01: no hardware check, no install. The 6.18 result
  of 20261020.02 and the 7.2 result of 20261015.01 (already carried over by
  20261020.01 and 20261020.02) are carried over again because the module
  payload is identical to that of 20261020.02 apart from the version
  string. NOT VERIFIED on 6.18 as before: suspend/resume, Bluetooth
  function, the rebind recovery in action.

## 20261020.02

**6.18: hardware gate run, partly verified.** The package builds for the
CachyOS LTS kernel 6.18 as well as for 7.2. On `6.18.55-2-cachyos-lts`,
`macbook91-wireless-verify` reports 0 FAIL and 0 WARN with the 20261020.02
modules loaded and WLAN up (VERIFIED 2026-10-20). Suspend/resume, Bluetooth
function and the rebind recovery on 6.18 are NOT VERIFIED. The 7.2 modules
are unchanged in source.

- New patch series `patches/6.18/`: the twelve patches of `patches/7.2/`
  rebased onto kernel.org v6.18.55 with line offsets only (`patch -F0`, no
  fuzz). `packaging/upstream.lock` pins v6.18.55 next to v7.2.9.
- The package carries one source tree per kernel series, `series/6.18/` and
  `series/7.2/`, each with its own manifest. The source identity of the 7.2
  modules is unchanged, `20261020.02+494451d9a8ce5f25` (the manifest keeps
  its lines, so its hash stays that of the flat tree; a test pins it); the
  6.18 modules carry `20261020.02+2eed8ec6343efe4f`.
- `packaging/fetch-upstream.sh` assembles every series of the lockfile
  (newest tag per series by default, `--tag` repeatable) and writes the list
  of series to `KERNEL-SERIES`.
- The module Makefile takes the series from the target kernel's
  `utsrelease.h`, builds that series, and copies the five modules to
  `build/`, which `dkms.conf` names for all of them. A kernel of a series
  the tree does not carry is skipped with status 0.
- `dkms.conf`: `BUILD_EXCLUSIVE_KERNEL` is generated from the series list,
  `^(6\.18|7\.2)\.`; other kernels keep their stock drivers.
- The install scriptlet and `macbook91-wireless-verify` know a list of
  series ("not one of Linux 6.18, 7.2"); the verifier compares the loaded
  modules with the manifest of the running kernel's series.
- PKGBUILD: `linux-cachyos-lts-headers` in `optdepends`.
- Tests: the DKMS pattern against the series list, offline reassembly of
  every series, `patches/<series>` for every lock tag, the skip of an
  unshipped series, the LE fixup host test per series, and the pinned 7.2
  source identity.
- Build checks (VERIFIED 2026-10-20): all five modules build against
  `7.2.11-1-cachyos` (clang) and `6.18.55-2-cachyos-lts` (gcc) with 0
  warnings.
- Install and runtime on 6.18 (VERIFIED 2026-10-20, run by the maintainer):
  `pacman -U` exit 0, DKMS installed the package for
  `6.18.55-2-cachyos-lts` and `7.2.11-1-cachyos`. After booting 6.18,
  `macbook91-wireless-verify` reports 0 FAIL and 0 WARN: `brcmfmac`,
  `brcmfmac-wcc` and `hci_uart` `20261020.02+2eed8ec6343efe4f` loaded, chip
  reset across system sleep on, rebind recovery on, P2P off, WLAN BCM4350
  up, no WLAN or Bluetooth errors in the journal.
- NOT VERIFIED on 6.18: suspend/resume (no suspend happened in that boot),
  Bluetooth function (`hci0` was present but blocked by rfkill, so
  Bluetooth was not exercised), the rebind recovery in action.
- NOT VERIFIED on 7.2: the runtime of 20261020.02 was not run; it is
  carried over, since the module code is identical to 20261020.01 (the 7.2
  modules built from both have the same disassembly and the same modinfo
  apart from version and srcversion).

## 20261020.01

Twelve patches against kernel.org v7.2.9, unchanged since 20261015.01; the
module code is the same, the two Kbuild files gain only license comments.

- `macbook91-wireless-verify`: the P2P check reads the last
  `feature_disable` value modprobe.d sets and tests its bit 0x10. It used to
  report P2P off for any line with exactly `0x10`, even when a later file
  overrode it, and on for values such as `0x30`.
- modprobe.d: the comment names the reliable override, a file of the same
  name in `/etc/modprobe.d/`.
- License: this project's own files are GPL-3.0-or-later (they were
  GPL-2.0-or-later) and name their license in an SPDX line. The files that
  build the modules stay GPL-2.0-or-later, since GPLv2 requires them with a
  built module: the module tree's `Makefile` and `dkms.conf` and
  `packaging/overlay/brcm80211.Kbuild`; `packaging/overlay/bluetooth.Kbuild`
  is GPL-2.0-only, as its object list is that of the kernel's Makefile.
  Kernel files and the patches keep the kernel file's license; the LE fixup
  host test stays GPL-2.0-or-later. `hci_ll.c`, `hci_qca.c` and `btqca.h`
  are GPL-2.0-only, `hci_aml.c` GPL-2.0-only OR MIT. `LICENSES/` adds the
  GPL-2.0 and MIT texts, the package installs the MIT text next to ISC, and
  the PKGBUILD lists GPL-3.0-or-later, GPL-2.0-or-later, GPL-2.0-only, ISC
  and MIT.
- README: `clang lld llvm` are needed for clang-built kernels; the license
  section maps each path to its license.
- Tests: the e-mail check runs per file; one stream made `grep -I` stop at
  the first release tarball. A new check compares the license texts, the
  PKGBUILD's licenses and every own file's SPDX line with the license
  mapping.
- Documentation: project state of 2026-10-20, FINDINGS (sleep hooks, rtkit),
  STRUCTURE lists `docs/NAMCAP.md`, the LUKS UUID in
  `diag/2026-10-13/versions.txt` is redacted.
- Language: what this project wrote in German is now English: the
  findings, the project state, the first diagnosis (renamed to
  `DIAGNOSIS.md`), the notes in `diag/`, and project-internal task notes,
  plans and workflow messages (not part of this repository). Status markers read
  VERIFIED, NOT VERIFIED, REFUTED, HYPOTHESIS and REPORTED. Recorded
  command output stays as captured.

## 20261015.01

Twelve patches against kernel.org v7.2.9 (two revised):

- hci_bcm: the LE advertising fixup takes its flag from `bcm_data`, copied
  when the line discipline opens, instead of reading the device in the
  receive path (0009).
- hci_bcm: the speed change to the speed the controller already runs at is
  left out on Macs only; other machines keep upstream behaviour (0010).
  Both tested on the test machine: setup without warnings, LE scan without "unknown
  advertising packet type" warnings.
- `macbook91-wireless-verify` reads the journal from the time the modules
  were loaded (it used the time sysfs first showed their directory) and,
  without that time, the whole boot (it read nothing); `--help` shows the
  whole usage.
- Tests check `promote-release.sh` and `make-package.sh` as well.
- Documentation: 20261014.01 verified on the test machine (no `unlocked secondary bus
  reset` after two resumes), no Wake-on-WLAN with `pm_reset`, hibernation
  not tested.

## 20261014.01

Twelve patches against kernel.org v7.2.9 (two new):

- brcmfmac: the reset on resume (`pm_reset`) locks the parent bridge's
  config space, as `pci_reset_function()` does; the PCI core no longer warns
  `unlocked secondary bus reset` on the first resume of each boot (0011).
- brcmfmac: no recovery is queued once module exit has begun (0012).
- `macbook91-wireless-verify` checks `brcm/brcmfmac4350c2-pcie.bin`, the
  file brcmfmac loads for revision 5 of the BCM4350.
- Documentation: the regulatory domain as a user step, the Bluetooth
  message `Failed to set mode` while Bluetooth is switched off, and other
  messages that are not faults.
- Repository: no Python bytecode tracked; `make test` writes none.

## 20261013.01

First release. Package `macbook91-wireless-dkms`, built by DKMS for Linux 7.2
kernels from kernel.org v7.2.9 sources and ten patches:

- brcmfmac: reset the chip across system sleep (`pm_reset`), recover a hung
  firmware by unbind, bus reset and probe (`reset_rebind`), treat repeated
  command timeouts as a hang, remove before and probe after a PCI function
  reset, no error flood during an intended teardown, normal conditions of this
  firmware at debug level, informational messages at info level in debug
  builds.
- hci_bcm: set up the ROM firmware of Mac UART controllers without a patch
  search and without refused speed changes; clear reserved bits of LE
  advertising event types on Macs.
- modprobe.d: Wi-Fi P2P off.
- `macbook91-wireless-verify` checks build, loaded modules, parameters,
  firmware, sleep hooks, devices and the journal; `--reload` loads the
  installed modules without a reboot.

Not part of this release's tests: the long mixed suspend series (postponed),
Bluetooth audio and input devices across suspend (no paired device).
