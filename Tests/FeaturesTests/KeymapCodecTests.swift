import Testing
@testable import Features

@Test func packsCapturedEscKey() {
    let key = KeyInfo(
        type: 16,
        code1: 0,
        code2: 41,
        name: "Esc",
        index: 0
    )

    #expect(KeymapCodec.pack([key]) == [0x10, 0x00, 0x29])
}

@Test func keymapRoundTrip() {
    let keys = [
        KeyInfo(type: 16, code1: 0, code2: 41, name: "Esc", index: 0),
        KeyInfo(type: 16, code1: 0, code2: 12, name: "I", index: 1),
        KeyInfo(type: 255, code1: 0, code2: 0, name: "空", index: 2),
    ]

    let packed = KeymapCodec.pack(keys)
    let unpacked = KeymapCodec.unpack(packed, maxKeys: 3)

    #expect(unpacked == keys)
}

@Test func mapsCommonHIDUsages() {
    #expect(KeyNameMap.hidName(0x04) == "A")
    #expect(KeyNameMap.hidName(0x1D) == "Z")
    #expect(KeyNameMap.hidName(0x1E) == "1")
    #expect(KeyNameMap.hidName(0x29) == "Esc")
    #expect(KeyNameMap.hidName(0x2C) == "Space")
}
