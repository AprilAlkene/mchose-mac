import Foundation

/// One 4-byte step of a macro action stream.
///
/// Layout (vendor SDK `SerializeMacroActionItem`):
/// `[delay lo, delay hi, isEnd | isDown | type, code]`. `delay` is in
/// milliseconds and is the wait *before* this action; the vendor SDK writes
/// `MIN_MACRO_DELAY - 1` (4) when there is no explicit delay.
public struct MacroAction: Codable, Equatable, Sendable {
    public static let kindMouse: Int = 0
    public static let kindKeyboard: Int = 17
    public static let kindKeyboardControl: Int = 18
    public static let kindPlaceholder: Int = 63

    public var delay: UInt16
    public var kind: Int
    public var isDown: Bool
    public var isEnd: Bool
    public var code: UInt8

    public init(
        delay: UInt16 = 4,
        kind: Int = MacroAction.kindKeyboard,
        isDown: Bool = true,
        isEnd: Bool = false,
        code: UInt8
    ) {
        self.delay = delay
        self.kind = kind
        self.isDown = isDown
        self.isEnd = isEnd
        self.code = code
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 4 else { return nil }
        delay = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        kind = Int(bytes[2] & 0x3F)
        isDown = bytes[2] & 0x40 != 0
        isEnd = bytes[2] & 0x80 != 0
        code = bytes[3]
    }

    public var bytes: [UInt8] {
        var flags = UInt8(kind & 0x3F)
        if isDown { flags |= 0x40 }
        if isEnd { flags |= 0x80 }
        return [
            UInt8(delay & 0xFF),
            UInt8((delay >> 8) & 0xFF),
            flags,
            code,
        ]
    }

    public var isPlaceholder: Bool {
        kind == MacroAction.kindPlaceholder && code == 0
    }

    /// Human-readable description, e.g. `A down` / `mouse 1 up`.
    public var description: String {
        switch kind {
        case MacroAction.kindKeyboard:
            return "\(KeyNameMap.hidName(code)) \(isDown ? "down" : "up")"
        case MacroAction.kindKeyboardControl:
            return "Ctrl 0x\(String(format: "%02X", code)) \(isDown ? "down" : "up")"
        case MacroAction.kindMouse:
            return "鼠标 \(code + 1) \(isDown ? "down" : "up")"
        default:
            return "type \(kind) code 0x\(String(format: "%02X", code))"
        }
    }
}

/// One of the 16 shared macro slots.
public struct MacroSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var type: UInt8
    public var actions: [MacroAction]

    public init(index: Int, type: UInt8 = 0, actions: [MacroAction] = []) {
        self.index = index
        self.type = type
        self.actions = actions
    }
}

/// Codec for the shared 8192-byte macro area.
///
/// Header: 16 little-endian uint16 offsets, magic `0x81 0x7E`, then 16 type
/// bytes. The 4-byte empty-action marker lives at offset 64 and every empty
/// slot points there; non-empty streams start at 68.
public enum MacroCodec {
    public static let areaSize = 8192
    public static let headerSize = 64
    public static let slotCount = 16
    public static let emptyOffset: UInt16 = 64
    public static let emptyActionBytes: [UInt8] = [0x04, 0x00, 0x80, 0x00]
    public static let magic: [UInt8] = [0x81, 0x7E]

    public static func serialize(_ slots: [MacroSlot]) -> [UInt8] {
        let padded = (0..<slotCount).map { index in
            slots.first(where: { $0.index == index })
                ?? MacroSlot(index: index)
        }

        var offsets = [UInt16](repeating: emptyOffset, count: slotCount)
        var types = [UInt8](repeating: 0, count: slotCount)
        var body: [UInt8] = []
        var dedup: [[UInt8]: UInt16] = [:]
        var nextOffset = UInt16(headerSize + emptyActionBytes.count)

        for slot in padded {
            types[slot.index] = slot.type
            guard !slot.actions.isEmpty else { continue }
            let stream = slot.actions.flatMap(\.bytes)
            if let existing = dedup[stream] {
                offsets[slot.index] = existing
                continue
            }
            offsets[slot.index] = nextOffset
            dedup[stream] = nextOffset
            body.append(contentsOf: stream)
            nextOffset += UInt16(stream.count)
        }

        var result = [UInt8](repeating: 0, count: headerSize)
        for (index, offset) in offsets.enumerated() {
            result[index * 2] = UInt8(offset & 0xFF)
            result[index * 2 + 1] = UInt8((offset >> 8) & 0xFF)
        }
        result[32] = magic[0]
        result[33] = magic[1]
        for (index, type) in types.enumerated() {
            result[34 + index] = type
        }
        result.append(contentsOf: emptyActionBytes)
        result.append(contentsOf: body)
        return result
    }

    public static func parse(_ bytes: [UInt8]) -> [MacroSlot] {
        guard bytes.count >= headerSize else { return [] }
        let offsets = (0..<slotCount).map { index in
            UInt16(bytes[index * 2]) | (UInt16(bytes[index * 2 + 1]) << 8)
        }
        let hasMagic = bytes[32] == magic[0] && bytes[33] == magic[1]
        return (0..<slotCount).map { index in
            let offset = Int(offsets[index])
            let type = hasMagic ? bytes[34 + index] : 0
            guard offset != Int(emptyOffset),
                  offset >= headerSize,
                  offset < bytes.count else {
                return MacroSlot(index: index, type: type)
            }
            var actions: [MacroAction] = []
            var cursor = offset
            while cursor + 4 <= bytes.count {
                guard let action = MacroAction(bytes: Array(bytes[cursor..<cursor + 4])) else {
                    break
                }
                actions.append(action)
                cursor += 4
                if action.isEnd { break }
            }
            return MacroSlot(index: index, type: type, actions: actions)
        }
    }

    /// Number of bytes that must be read to cover the header and every slot's
    /// action stream (without the trailing area padding).
    public static func requiredByteCount(_ bytes: [UInt8]) -> Int {
        guard bytes.count >= headerSize else { return headerSize }
        var end = headerSize + emptyActionBytes.count
        for index in 0..<slotCount {
            let offset = Int(
                UInt16(bytes[index * 2]) | (UInt16(bytes[index * 2 + 1]) << 8)
            )
            guard offset >= headerSize, offset < areaSize else { continue }
            var cursor = offset
            while cursor + 4 <= bytes.count {
                let flags = bytes[cursor + 2]
                cursor += 4
                if flags & 0x80 != 0 { break }
            }
            end = max(end, cursor)
        }
        return min(max(end, headerSize), areaSize)
    }
}
