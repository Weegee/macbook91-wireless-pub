# namcap

`namcap` on the 20261021.01 package and PKGBUILD (no findings for the
PKGBUILD), after the fix below:

- `No ELF files and not an "any" package` (W): the package ships sources for
  DKMS; it stays `x86_64` like macbook91-cs4208, since the modules are only
  built and used on this x86_64 machine.
- `Dependency bash detected and implicitly satisfied` (W): bash is in the
  base system.
- `Dependency included, but may not be needed ('dkms')`, `('linux-firmware-broadcom')`
  (W): namcap cannot see that DKMS builds the sources or that the driver
  loads `brcm/brcmfmac4350c2-pcie.bin`; both are required.

Fixed: `Uncommon license identifiers such as 'ISC' require license files`
(E) - LICENSES/ISC and LICENSES/MIT are installed to
/usr/share/licenses/macbook91-wireless-dkms/.
