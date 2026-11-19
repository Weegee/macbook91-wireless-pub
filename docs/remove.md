# Remove the package

1. Remove the package. DKMS removes the modules with it; nothing outside the
   package's own files changes:

   ```fish
   sudo pacman -R macbook91-wireless-dkms
   ```

2. Reboot, or unload and load `brcmfmac` and `hci_uart`, so that the drivers of
   the kernel come back.

3. Check that the module no longer comes from DKMS:

   ```fish
   modinfo -F filename brcmfmac
   ```

   The path must not contain `updates/dkms`. With the package installed it
   reads `/lib/modules/7.3.3-1-cachyos/updates/dkms/brcmfmac.ko.zst`.

Not checked: the removal and the check after it (they need root).
