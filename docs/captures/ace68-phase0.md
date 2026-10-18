# Ace 68 Turbo 16K — Phase 0 capture

- Date: 2026-10-18
- Browser: Microsoft Edge 155.0.4283.62 (WebHID)
- Native: mchose-cli (IOKit)
- Device: MCHOSE Ace 68 Turbo 16K, VID `0x3837`, PID `0x3026`
- Config interface: usagePage `0x01`, usage `0x00`, reportId 0, 64-byte input/output
- Request flag: `0x55`
- Response flag: `0xAA`
- Command: `0x03` (getInfo)

## Request (64 bytes, reportId 0)

```text
55 03 00 38 38 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

## Response (64 bytes, reportId 0)

```text
AA 03 00 AD 1B 00 00 00 26 01 FF FF FF FF 00 4A
75 6C 20 32 31 20 32 30 32 36 2C 31 35 3A 31 36
3A 31 39 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

## Response header layout

| Offset | Meaning | Captured value |
|---|---|---|
| 0 | flag | `0xAA` |
| 1 | command | `0x03` |
| 2 | status/sequence (unclassified) | `0x00` |
| 3 | unclassified | `0xAD` |
| 4 | payload length | `0x1B` = 27 |
| 5..6 | payload offset, little-endian | `0x0000` |
| 7 | reserved | `0x00` |
| 8.. | payload | 27 bytes |

## Payload (27 bytes)

```text
26 01 FF FF FF FF 00 4A 75 6C 20 32 31 20 32 30
32 36 2C 31 35 3A 31 36 3A 31 39
```

- First 7 bytes: `26 01 FF FF FF FF 00`
- Remaining 20 bytes: ASCII `Jul 21 2026,15:16:19` (firmware build date)
- Web SDK `getInfo` result: `fw_ver=126`, `rffw_ver=ffff`, `collabType=255`, `isReportRateEnhanced=false`, `isU3Mode=false`

## Checksum

No checksum was observed for command 3: the last byte of both the request and the response is `0x00`. Do not add a checksum until another command demonstrates one.

## Native verification

`swift run mchose-cli info 0` returned the identical response on 2026-10-18.

The web SDK sends the same request twice during setup and receives the same response twice. The native CLI sends it up to twice and stops on the first matching response.

## Important implementation detail

IOKit input callbacks do not arrive unless the device is scheduled on the current run loop:

```swift
IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
```

Without this call, the request is sent but the response is never delivered to the app.
