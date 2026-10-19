import Testing
@testable import Features

@Test func patchesAndReadsLightConfig() {
    var config = [UInt8](repeating: 0, count: 64)
    let light = LightConfig(
        effect: 11,
        brightness: 4,
        speed: 2,
        direct: 0,
        customColorDisabled: 1,
        colorIndex: 0,
        hexColor: "#FF0000",
        sideEffect: 0,
        sideBrightness: 4,
        sideSpeed: 3,
        sideCustomColorDisabled: 1,
        sideHexColor: "#00FF00"
    )

    config = FuncConfigCodec.patch(light, into: config)
    #expect(config[8] == 11)
    #expect(config[9] == 4)
    #expect(config[10] == 2)
    #expect(config[14] == 0xFF)
    #expect(config[29] == 0x00)
    #expect(config[30] == 0xFF)

    let decoded = FuncConfigCodec.light(from: config)
    #expect(decoded == light)
}

@Test func parsesBaseInfo() {
    let bytes: [UInt8] = [0, 3, 0, 1, 2, 3]
    let base = BaseCodec.parse(bytes)
    #expect(base?.profileIndex == 0)
    #expect(base?.profileCount == 4)

    let switched = BaseCodec.setProfileIndex(2, in: bytes)
    #expect(switched[0] == 2)
}
