import Foundation
import Testing
@testable import Features

private func makeSnapshot() -> DeviceSnapshot {
    DeviceSnapshot(
        product: "Ace 68 Turbo 16K",
        firmwareVersion: "126",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        profileIndex: 1,
        triggers: [],
        keymap: [],
        funcConfig: Array(repeating: 0, count: 64),
        base: Array(repeating: 0, count: 56)
    )
}

@Test func rgbColorParsesHexWithAndWithoutHash() {
    #expect(KeyColor(hex: "#FF8001") == KeyColor(red: 0xFF, green: 0x80, blue: 0x01))
    #expect(KeyColor(hex: "00ff00") == KeyColor(red: 0, green: 0xFF, blue: 0))
    #expect(KeyColor(hex: "#12345") == nil)
    #expect(KeyColor(hex: "#GG0000") == nil)
    #expect(KeyColor(red: 0x12, green: 0x34, blue: 0x56).hex == "#123456")
}

@Test func perKeyLightCodecRoundTrips() {
    let colors = [
        KeyColor(red: 1, green: 2, blue: 3),
        KeyColor(red: 4, green: 5, blue: 6),
        KeyColor.off,
    ]
    let bytes = PerKeyLightCodec.pack(colors)
    #expect(bytes == [1, 2, 3, 4, 5, 6, 0, 0, 0])
    #expect(PerKeyLightCodec.unpack(bytes) == colors)
}

@Test func perKeyLightCodecTruncatesToMaxKeys() {
    let bytes = Array(repeating: UInt8(7), count: 3 * 4)
    #expect(PerKeyLightCodec.unpack(bytes, maxKeys: 2).count == 2)
    #expect(PerKeyLightCodec.unpack([1, 2]).isEmpty)
}

@Test func snapshotRoundTripsPerKeyColors() throws {
    let colors = [
        KeyColor(red: 0xFF, green: 0, blue: 0),
        KeyColor(red: 0, green: 0x80, blue: 0xFF),
    ]
    let snapshot = DeviceSnapshot(
        product: "Ace 68 Turbo 16K",
        firmwareVersion: "126",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        profileIndex: 1,
        triggers: [],
        keymap: [],
        keyColors: colors,
        funcConfig: Array(repeating: 0, count: 64),
        base: Array(repeating: 0, count: 56)
    )
    let encoded = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: encoded)
    #expect(decoded == snapshot)
    #expect(decoded.keyColors == colors)
}

@Test func legacySnapshotWithoutKeyColorsDecodesWithNilColors() throws {
    let encoded = try JSONEncoder().encode(makeSnapshot())
    let object = try JSONSerialization.jsonObject(with: encoded)
    var dict = object as? [String: Any] ?? [:]
    dict.removeValue(forKey: "keyColors")
    let data = try JSONSerialization.data(withJSONObject: dict)
    let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
    #expect(decoded.keyColors == nil)
}
