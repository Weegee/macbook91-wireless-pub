# Install the package

Install from the files of a release. There is no package repository and the
packages are unsigned. DKMS compiles kernel modules that run in your kernel,
so read the code before you build. To build from a checkout instead, see
[entwicklung/bauen.md](entwicklung/bauen.md).

You need a MacBook9,1 with CachyOS or another Arch-based system, `base-devel`
(for `makepkg`) and the headers of every kernel you want the modules for (see
[kernels.md](kernels.md)). `makepkg -s` installs `dkms`, `linux-firmware-broadcom`
and `linux-cachyos-lts-headers`.

1. Download all files of the latest
   [release](https://github.com/Weegee/macbook91-wireless-pub/releases/latest)
   into one empty directory. `makepkg` needs `PKGBUILD`,
   `macbook91-wireless.install` and `macbook91-wireless-dkms-VERSION.tar`;
   `SHA256SUMS` lists the files to check.

   > **Warning:** `--ignore-missing` skips every line of `SHA256SUMS` whose
   > file is not there, so step 2 can succeed while the install file or the
   > tarball is missing. GitHub serves `.SRCINFO` as `default.SRCINFO`, so that
   > line is always skipped. Run step 3 only when `PKGBUILD`,
   > `macbook91-wireless.install` and the tarball all read `OK`.

2. In that directory, check the files:

   ```fish
   sha256sum -c --ignore-missing SHA256SUMS
   ```

   Output for release 20261102.01 (the `.SRCINFO` line is skipped):

   ```text
   PKGBUILD: OK
   macbook91-wireless.install: OK
   upstream.lock: OK
   STATUS.txt: OK
   macbook91-wireless-dkms-20261102.01.tar: OK
   ```

   A `FAILED` line means: do not build.

3. Build the package and install it. The PKGBUILD pins the SHA-256 of the
   tarball. DKMS builds the modules for every installed kernel of a supported
   series:

   ```fish
   makepkg -si
   ```

4. Load the modules. WLAN and Bluetooth drop for a few seconds; a reboot does
   the same:

   ```fish
   sudo macbook91-wireless-verify --reload
   ```

5. Check the result. The last line must read `PASS: 0 FAIL, 0 WARN`
   ([check.md](check.md)):

   ```fish
   macbook91-wireless-verify
   ```

To go back, see [remove.md](remove.md).

Checked on 2026-11-09: step 2 on the files of release 20261102.01. Not
checked for this version: steps 3 and 4 (they need root).
