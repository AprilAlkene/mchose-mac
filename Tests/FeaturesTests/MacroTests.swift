import Foundation
import Testing
@testable import Features

private func emptySlots() -> [MacroSlot] {
    (0..<MacroCodec.slotCount).map { MacroSlot(index: $0) }
}

@Test func emptyMacroAreaMatchesVendorLayout() {
    let bytes = MacroCodec.serialize(emptySlots())
    #expect(bytes.count == MacroCodec.headerSize + 4)
    #expect(Array(bytes[32..<34]) == [0x81, 0x7E])
    for index in 0..<MacroCodec.slotCount {
        let offset = UInt16(bytes[index * 2]) | (UInt16(bytes[index * 2 + 1]) << 8)
        #expect(offset == MacroCodec.emptyOffset)
    }
    #expect(Array(bytes[64..<68]) == [0x04, 0x00, 0x80, 0x00])
}

@Test func macroSerializationRoundTripsActions() {
    var slots = emptySlots()
    slots[3] = MacroSlot(
        index: 3,
        type: 2,
        actions: [
            MacroAction(isDown: true, code: 0x04),
            MacroAction(isDown: false, isEnd: true, code: 0x04),
        ]
    )
    let bytes = MacroCodec.serialize(slots)
    #expect(bytes.count == 64 + 4 + 8)
    let offset = Int(UInt16(bytes[6]) | (UInt16(bytes[7]) << 8))
    #expect(offset == 68)
    #expect(bytes[37] == 2)

    let parsed = MacroCodec.parse(bytes)
    #expect(parsed[3].actions == slots[3].actions)
    #expect(parsed[0].actions.isEmpty)
    #expect(MacroCodec.requiredByteCount(bytes) == 76)
}

@Test func macroActionsEncodeVendorFlags() {
    let down = MacroAction(isDown: true, code: 0x04).bytes
    #expect(down == [0x04, 0x00, 0x40 | 0x11, 0x04])
    let up = MacroAction(isDown: false, isEnd: true, code: 0x04).bytes
    #expect(up == [0x04, 0x00, 0x80 | 0x11, 0x04])
    #expect(MacroAction(bytes: up)?.isEnd == true)
    #expect(MacroAction(bytes: up)?.isDown == false)
    #expect(MacroAction(bytes: [1, 2, 3]) == nil)
}

@Test func macroCodecDeduplicatesIdenticalStreams() {
    let actions = [
        MacroAction(isDown: true, code: 0x04),
        MacroAction(isDown: false, isEnd: true, code: 0x04),
    ]
    var slots = emptySlots()
    slots[0] = MacroSlot(index: 0, actions: actions)
    slots[1] = MacroSlot(index: 1, actions: actions)
    let bytes = MacroCodec.serialize(slots)
    #expect(bytes.count == 64 + 4 + 8)
    let offset0 = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    let offset1 = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
    #expect(offset0 == offset1)
}

@Test func macroParsesEmptyHardwareHeader() {
    var bytes = [UInt8](repeating: 0, count: 68)
    for index in 0..<MacroCodec.slotCount {
        bytes[index * 2] = 64
    }
    bytes[32] = 0x81
    bytes[33] = 0x7E
    bytes[64] = 0x04
    bytes[65] = 0x00
    bytes[66] = 0x80
    let slots = MacroCodec.parse(bytes)
    #expect(slots.count == 16)
    #expect(slots.allSatisfy { $0.actions.isEmpty })
    #expect(MacroCodec.requiredByteCount(bytes) == 68)
}

@Test func macroBytesRoundTripThroughSnapshot() throws {
    let macroBytes = MacroCodec.serialize(emptySlots())
    let snapshot = DeviceSnapshot(
        product: "Ace 68 Turbo 16K",
        firmwareVersion: "126",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        profileIndex: 1,
        triggers: [],
        keymap: [],
        macroBytes: macroBytes,
        funcConfig: Array(repeating: 0, count: 64),
        base: Array(repeating: 0, count: 56)
    )
    let encoded = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: encoded)
    #expect(decoded.macroBytes == macroBytes)
}

@Test func legacySnapshotWithoutMacroBytesDecodesNil() throws {
    let snapshot = DeviceSnapshot(
        product: "Ace 68 Turbo 16K",
        firmwareVersion: "126",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        profileIndex: 0,
        triggers: [],
        keymap: [],
        funcConfig: Array(repeating: 0, count: 64),
        base: Array(repeating: 0, count: 56)
    )
    let encoded = try JSONEncoder().encode(snapshot)
    var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
    dict.removeValue(forKey: "macroBytes")
    let data = try JSONSerialization.data(withJSONObject: dict)
    let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
    #expect(decoded.macroBytes == nil)
}
