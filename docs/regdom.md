# Set the regulatory domain (optional)

Until a country is set in `/etc/conf.d/wireless-regdom`, udev logs
`cfg80211: Process '/usr/bin/set-wireless-regdom' failed with exit code 1`
once per boot. The package cannot set it: the file belongs to `wireless-regdb`.
On CachyOS, `cachyos-iw-set-regdomain.service` already sets the domain from the
time zone; this step removes the message and applies the country from the start.

1. Enable the country. This example is for Germany; for another country
   replace `DE` in both places with its two-letter code:

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
limits the channels instead ([FINDINGS.md](FINDINGS.md#regulatory-domain)).
Checked on 2026-11-09: the `sed` pattern matches one line of the file (the file
was not written). Not checked: both `sed -i` commands.
