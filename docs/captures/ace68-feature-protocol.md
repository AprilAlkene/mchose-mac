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
- **All reads are addressed.** The vendor SDK's `_simpleGetCommand` sends one
  request per page at `offset + pageStart` (page size 56) and the device echoes
  that logical address in the response header. `CZResponseAssembler` orders
  replies by offset when the offsets are unique (the normal case) and falls
  back to arrival order otherwise.

## Commands

| Purpose | Request cmd | Response cmd | Data / offset |
|---|---|---|---|
| getInfo | `0x03` | `0x03` | 56-byte request; response payload starts at 8 |
| Base read | `0x04` | `0x04` | 56 bytes at offset `0` |
| Func config read | `0x05` | `0x05` | 64 bytes at offset `64 * profile` (page 56 + page 8) |
| Func config write | `0x06` | `0x06` | 64 bytes at offset `64 * profile`, 56-byte chunks with overlap |
| Keymap read | `0x08` | `0x08` | 384 bytes (`usedKeyAreaSize`) at offset `512 * (4 * profile + layer)` |
| Keymap write | `0x09` | `0x09` | 384 bytes (3 bytes/key) at the same offset, chunk size **54** |
| Base write / profile switch | `0x0E` | `0x0E` | 56-byte base struct at offset 0; byte 0 = profile index |
| Trigger read | `0xA0` | `0xA0` | 1024 bytes at offset `1024 * profile` (or 8 bytes at `+ 8 * keyIndex`) |
| Trigger write | `0xA1` | `0xA1` | 1024 bytes (8 bytes/key) at offset `1024 * profile`, 56-byte chunks |

The keymap area reserves 512 bytes per layer (`totalKeyAreaSize`) but only
384 bytes are used (`usedKeyAreaSize = 3 * maxKeyCount`). Up to 4 profiles are
addressable (`MAX_KEYBOARD_PROFILE_LENGTH = 4`); this device's base struct
declares 3 active profiles, so keymap addresses are `0, 512, 1024, 1536` for
layers 0..3 of profile 0, `2048, 2560, ...` for profile 1, and so on.

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

The 64-byte func config is read with command `0x05`; light fields (confirmed
against the vendor SDK's `be`/`Ce` helpers, which read and rebuild exactly
these byte offsets):

```text
effect               = payload[8]        # main effect enum; 0..22 on this layout
brightness (0..100)  = payload[9]        # percent, official UI slider 0..100
speed (0..4)         = 4 - payload[10]   # inversion confirmed by vendor SDK
direct               = payload[11]       # direction, 0/1
customColorDisabled  = payload[12]       # 1 = random color, 0 = use custom RGB
colorIndex           = payload[13]       # palette index 0..6 (RGB wins)
main RGB             = payload[14..16]
side effect          = payload[24]       # 0 flow, 1 neon, 2 breathing,
                                         # 3 constant, 4 off
side brightness      = payload[25]       # percent, 0..100
side speed (0..4)    = 4 - payload[26]
side custom disabled = payload[27]       # 1 = random, 0 = custom
side RGB             = payload[29..31]   # byte 28 = side colorIndex (preserved)
```

> `customColorDisabled` is a **random color** flag, not "disable custom color":
> `1` means the firmware uses random colors and ignores the RGB bytes; `0`
> means the custom RGB is used. The app clears it for the corresponding light
> when the user picks a color, mirroring the vendor UI.
>
> Vendor main effects on this layout (0..22): custom, rainbow cycle, linear
> gradient, constant, breathing, disco, horizontal wave, vertical wave, center
> spread, star twinkle, center spin, bottom rise, bounce, key ripple, constant
> ripple, key ghost, key firework, key beam, diagonal flow, laser rain, dot
> twinkle, firework, triangle bounce. Side effects: 0 flowing, 1 neon,
> 2 breathing, 3 constant on, 4 off.

> Brightness range: an early capture wrongly documented 0..4. A live read on
> 2026-10-19 returned `brightness = 100` (`payload[9] = 0x64`) for both main and
> side lights, and the official web UI's lighting panel uses
> `<Slider min:0 max:100>` with a `%` label for brightness and `<Slider min:0
> max:4>` for speed (bundle chunk `app/1833-*.js`). `LightConfig` therefore
> treats brightness as a 0..100 percentage and clamps writes to that range.

### Base -> profile

The 56-byte base struct (`0x04` read / `0x0E` write) mirrors the vendor SDK's
`Ne()` decoder and `setBase()` writer:

```text
payload[0]     = slot index = order.indexOf(active profile)
payload[1]     = number of active profiles (this device: 3)
payload[2..5]  = profile order, a permutation of 0..<4
payload[6..7]  = magic bytes AA BB
...
```

- Logical active profile = `payload[order[slot]]` when the order is a
  permutation; the vendor decoder otherwise falls back to the slot value and
  reports 2 profiles.
- To switch profiles, read the base struct, replace `payload[0]` with
  `order.indexOf(target)`, and write the whole 56-byte struct back. There is no
  dedicated switch command.
- The device notifies profile changes on the input report path (`0xA1` =
  pre-notify, `0xA2` = active index).
- Live capture (active profile 1): `01 03 00 01 02 03 AA BB ...` → slot 1,
  3 active profiles, order `[0, 1, 2, 3]`, active profile index 1.

### Other commands observed in the vendor SDK (not implemented here)

| Purpose | Read / write |
|---|---|
| Keymap default (flash) / current | `0x07` / `0x08` |
| Per-key lighting | `0x0A` / `0x0B` (3 bytes/key, stride 512) |
| Macros | `0x0C` / `0x0D` |
| DKS / MT / TGL | `0xA2`–`0xA7` |
| Calibration | `0xA8` / `0xA9` / `0xB1` |
| Music colors | `0xDC` / `0xDD` / `0xDF`, realtime `0xDE` |
| Factory reset | `0xEE` |

The project deliberately implements only the read/write commands listed in the
command table above; everything else is out of scope (no OTA, no factory reset).

## Write safety

Every write path added in this project follows the same rules:

1. **Opt-in writes.** `mchose-cli` defaults to read-only. Writes require
   `--allow-write`; `--dry-run` encodes but does not send. The app accepts
   `--read-only` / `--dry-run` launch arguments.
2. **Readback verification.** `DeviceConnection.apply*` reads the section
   before writing, writes it, reads it back and compares. A mismatch triggers
   a best-effort write of the previous values before the error is reported.
3. **Snapshot before apply.** The app stores a JSON snapshot of triggers,
   keymap, func config and base in
   `~/Library/Application Support/MCHOSE Mac/Snapshots/` before every apply;
   `mchose-cli snapshot` / `restore` provide the same flow from the CLI.
4. **No OTA / boot commands.** The write command table above is the complete
   set of commands the project sends.

## Verified

`mchose-cli selfcheck --allow-write` reads the original values, writes them back, and reads them again:

```text
triggers match: true
keymap match: true
func match: true
base match: true
```

Profile switching was verified with `mchose-cli switchprofile 1` and `switchprofile 0`.

### Profile addressing verified on hardware (2026-10-19)

With active profile index 1, native addressed reads returned that profile's
data instead of profile 0's:

```text
readraw 05 0  64  -> ... 06 64 00 ...   effect 6,  red
readraw 05 64 64  -> ... 0E 64 01 ...   effect 14, white   # profile 1
readraw A0 0    16 -> A0 00 95 00 1D 1E ...
readraw A0 1024 16 -> A1 01 95 14 C1 0B ...                # profile 1
```

This confirmed the vendor SDK formulas (`512 * (4 * profile + layer)` for the
keymap, `1024 * profile` for triggers, `64 * profile` for func config) and
proved that forcing read offset 0 always returned profile 0's settings.
