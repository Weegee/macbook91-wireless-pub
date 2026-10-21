# diag

Command output and notes recorded on the test machine (a MacBook9,1) between
2026-10-13 and 2026-10-15. They are the raw material behind
[DIAGNOSIS.md](../DIAGNOSIS.md) and [docs/FINDINGS.md](../docs/FINDINGS.md).

- In the two `.log` files the host name of the machine is replaced by
  `testhost` and nothing else is changed (same lines, same order).
- `2026-10-14/live-tests.md` and `2026-10-15/live-tests.md` are written
  reports, not raw output. Their wording was made neutral for publication
  (the machine and the person running the tests are not named); their
  results are unchanged.
- The test machine's ACPI tables were decompiled for this research. The
  decompiled code is Apple's and is not part of this repository. In this
  project's words: the WLAN device ARPT sits under the root port RP09 (PCI
  address 0x001D0000) and has methods for its status, wake (`_PRW`), removal
  status (`_RMV`) and two vendor methods, WWEN and PDEN; the root port RP10
  carries the method CMPE, which acts on the camera device
  `\_SB_.PCI0.RP10.CMRA`. No Apple binaries or Apple code are included.
- No license is stated for the files in this directory (see
  [README.md](../README.md), section License).
