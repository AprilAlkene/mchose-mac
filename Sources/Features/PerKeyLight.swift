import Foundation

/// One per-key RGB color. The firmware stores three bytes per key and the
/// vendor SDK reads/writes the whole `usedLightAreaSize` (3 * 128) block with
/// command `0x0A` / `0x0B` at `totalLightAreaSize (512) * profile`.
public struct KeyColor: Codable, Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `#RRGGBB` / `RRGGBB` (leading `#` optional).
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            return nil
        }
        self.red = UInt8((number >> 16) & 0xFF)
        self.green = UInt8((number >> 8) & 0xFF)
        self.blue = UInt8(number & 0xFF)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public static let off = KeyColor(red: 0, green: 0, blue: 0)
}

public enum PerKeyLightCodec {
    public static func unpack(
        _ bytes: [UInt8],
        maxKeys: Int = DeviceMemoryMap.lightKeyCount
    ) -> [KeyColor] {
        let count = min(maxKeys, bytes.count / 3)
        return (0..<count).map { index in
            let base = index * 3
            return KeyColor(
                red: bytes[base],
                green: bytes[base + 1],
                blue: bytes[base + 2]
            )
        }
    }

    public static func pack(_ colors: [KeyColor]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(colors.count * 3)
        for color in colors {
            bytes.append(color.red)
            bytes.append(color.green)
            bytes.append(color.blue)
        }
        return bytes
    }
}
