# getInfo payload field mapping

Captured on 2026-10-18 from the web SDK decoder using a fake HID device and fabricated responses.

Base payload (27 bytes):

```text
26 01 FF FF FF FF 00 4A 75 6C 20 32 31 20 32 30 32 36 2C 31 35 3A 31 36 3A 31 39
```

| Payload byte | Base value | Variant | Decoded change | Meaning |
|---|---|---|---|---|
| 0 | `0x26` | `0x00` | `fw_ver` 126 → 100 | firmware minor version, two BCD hex digits |
| 1 | `0x01` | `0x00` | `fw_ver` 126 → 26 | firmware major version prefix |
| 2 | `0xFF` | `0x00` | `rffw_ver` ffff → ff00 | RF firmware low byte |
| 3 | `0xFF` | `0x00` | `rffw_ver` ffff → ff | RF firmware high byte |
| 4 | `0xFF` | not tested | — | unidentified; not used in Phase 1a |
| 5 | `0xFF` | not tested | — | unidentified; not used in Phase 1a |
| 6 | `0x00` | not tested | — | unidentified; not used in Phase 1a |
| 7..26 | ASCII | — | build date unchanged | `Jul 21 2026,15:16:19` |

## Decode formulas

- `fw_ver`:
  - `minor = String(format: "%02X", byte0)`
  - `major = byte1`
  - `major == 0 ? minor : "\(major)\(minor)"`
  - Confirmed: `0x01,0x26` → `126`; `0x00,0x26` → `26`; `0x01,0x00` → `100`.
- `rffw_ver`:
  - `value = UInt16(byte2) | (UInt16(byte3) << 8)`
  - `String(value, radix: 16)` (no leading zeros)
  - Confirmed: `FF,FF` → `ffff`; `00,FF` → `ff00`; `FF,00` → `ff`.
- Build date: last 20 payload bytes as UTF-8 ASCII.

`collabType`, `isReportRateEnhanced`, and `isU3Mode` were not mapped in Phase 1a and are not displayed yet.
