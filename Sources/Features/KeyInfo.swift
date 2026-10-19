import Foundation

public struct KeyInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public var type: UInt8
    public var code1: UInt8
    public var code2: UInt8
    public var name: String
    public var index: Int

    public init(
        type: UInt8,
        code1: UInt8,
        code2: UInt8,
        name: String,
        index: Int
    ) {
        self.type = type
        self.code1 = code1
        self.code2 = code2
        self.name = name
        self.index = index
    }
}

public enum KeymapCodec {
    public static func pack(_ keys: [KeyInfo]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(keys.count * 3)
        for key in keys {
            result.append(key.type)
            result.append(key.code1)
            result.append(key.code2)
        }
        return result
    }

    public static func unpack(_ bytes: [UInt8], maxKeys: Int) -> [KeyInfo] {
        let count = min(maxKeys, bytes.count / 3)
        return (0..<count).map { index in
            let base = index * 3
            let type = bytes[base]
            let code1 = bytes[base + 1]
            let code2 = bytes[base + 2]
            return KeyInfo(
                type: type,
                code1: code1,
                code2: code2,
                name: KeyNameMap.name(type: type, code1: code1, code2: code2),
                index: index
            )
        }
    }
}

public enum KeyNameMap {
    public static func name(type: UInt8, code1: UInt8, code2: UInt8) -> String {
        if type == 255 {
            return "空"
        }
        if type == 16 {
            return hidName(code2)
        }
        return "Type \(type) / 0x\(String(code2, radix: 16))"
    }

    /// Reverse lookup used by the CLI/testing to build macro actions.
    public static func hidUsage(forName name: String) -> UInt8? {
        let target = name.lowercased()
        for usage in UInt8(0)...UInt8(255) where hidName(usage).lowercased() == target {
            return usage
        }
        return nil
    }

    public static func hidName(_ usage: UInt8) -> String {
        switch usage {
        case 0x04...0x1D:
            let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            return String(letters[Int(usage - 0x04)])
        case 0x1E...0x27:
            let digits = Array("1234567890")
            return String(digits[Int(usage - 0x1E)])
        case 0x28: return "Enter"
        case 0x29: return "Esc"
        case 0x2A: return "Backspace"
        case 0x2B: return "Tab"
        case 0x2C: return "Space"
        case 0x2D: return "-"
        case 0x2E: return "="
        case 0x2F: return "["
        case 0x30: return "]"
        case 0x31: return "\\"
        case 0x33: return ";"
        case 0x34: return "'"
        case 0x35: return "`"
        case 0x36: return ","
        case 0x37: return "."
        case 0x38: return "/"
        case 0x39: return "CapsLock"
        case 0x3A...0x45:
            return "F\(Int(usage - 0x39))"
        case 0x46: return "PrtSc"
        case 0x47: return "ScrollLock"
        case 0x48: return "Pause"
        case 0x49: return "Insert"
        case 0x4A: return "Home"
        case 0x4B: return "PageUp"
        case 0x4C: return "Delete"
        case 0x4D: return "End"
        case 0x4E: return "PageDown"
        case 0x4F: return "Right"
        case 0x50: return "Left"
        case 0x51: return "Down"
        case 0x52: return "Up"
        case 0x53: return "NumLock"
        case 0xE0: return "LeftCtrl"
        case 0xE1: return "LeftShift"
        case 0xE2: return "LeftAlt"
        case 0xE3: return "LeftGUI"
        case 0xE4: return "RightCtrl"
        case 0xE5: return "RightShift"
        case 0xE6: return "RightAlt"
        case 0xE7: return "RightGUI"
        default:
            return "0x\(String(format: "%02X", usage))"
        }
    }
}
