# Ace 68 Turbo 16K — feature protocol

Derived from the web SDK (`CZ_SHARED_DATA`) and verified with `mchose-cli selfcheck`.

## Request frame

```text
55 <command> 00 <checksum> <size> <offsetLo> <offsetHi> 00 <data...> <padding to 64>
```

- `checksum` = sum of `[size, offsetLo, offsetHi, 0, ...data]` & 0xFF.
- `size` is the number of data bytes in this packet (max 56).
- `offset` is the logical address for writes / addressed reads.

## Response frame

```text
AA <command> 00 <?> <length> <offsetLo> <offsetHi> 00 <payload...> <padding>
```

- Payload always starts at byte 8.
- `length` is the payload length in this packet.
- The offset field is the logical address, not an in-packet payload offset.

## Commands

| Purpose | Request cmd | Response cmd | Data |
|---|---|---|---|
| Base info | `0x04` | `0x04` | 56 bytes, one page |
| Func config read | `0x05` | `0x05` | 64 bytes: page 56 at offset 0 + page 8 at offset 56 |
| Func config write | `0x06` | `0x06` | 64 bytes, 56-byte chunks with overlap |
| Keymap read | `0x08` | `0x08` | 384 bytes; page requests use offset 0; stream may start with a 6-byte carry-over |
| Keymap write | `0x09` | `0x09` | 384 bytes (3 bytes/key), chunk size **54** |
| Base write / profile switch | `0x0E` | `0x0E` | 56-byte base struct; byte 0 = profile index |
| Trigger read | `0xA0` | `0xA0` | 1024 bytes; page requests use offset 0 |
| Trigger write | `0xA1` | `0xA1` | 1024 bytes (8 bytes/key), 56-byte chunks |

## Key encodings

### Trigger (8 bytes/key)

```text
b0 = 160 | switchType
b1 = (priority << 4) | keyMode
b2 = (keyActuation - 1) & 0xFF
b3 = ((keyActuation - 1) >> 8 & 1) | (pressPrecision & 3) << 3 | (releasePrecision & 3) << 1
b4 = (rtPress - 1) & 0xFF
b5 = ((rtPress - 1) >> 8 & 1) | (pressDeadzone & 0x7F) << 1
b6 = (rtRelease - 1) & 0xFF
b7 = ((rtRelease - 1) >> 8 & 1) | (releaseDeadzone & 0x7F) << 1
```

### Keymap (3 bytes/key)

```text
[type, code1, code2]
```

Standard keyboard keys use type 16 and a HID usage in `code2` (Esc = 41, A = 4, Space = 44).

### Func config -> light

The 64-byte func config is read with command `0x05`; light fields:

```text
effect               = payload[8]
brightness (0..4)    = payload[9]
speed (0..4)         = 4 - payload[10]
direct               = payload[11]
customColorDisabled  = payload[12]
colorIndex           = payload[13]
main RGB             = payload[14..16]
side effect          = payload[24]
side brightness      = payload[25]
side speed (0..4)    = 4 - payload[26]
side custom disabled = payload[27]
side RGB             = payload[29..31]
```

### Base -> profile

```text
payload[0] = active profile index (0-based)
payload[1] = profile length; profile count = payload[1] + 1
```

## Verified

`mchose-cli selfcheck` reads the original values, writes them back, and reads them again:

```text
triggers match: true
keymap match: true
func match: true
base match: true
```

Profile switching was verified with `mchose-cli switchprofile 1` and `switchprofile 0`.
