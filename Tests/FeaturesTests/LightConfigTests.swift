import Testing
import HIDTransport
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

@Test func clampsBrightnessToOfficialRange() {
    // The official web UI exposes brightness as a 0..100 percent slider and
    // speed as a 0..4 slider.
    let light = LightConfig(
        brightness: 200,
        speed: 9,
        sideBrightness: 250,
        sideSpeed: 7
    )
    let patched = FuncConfigCodec.patch(
        light,
        into: [UInt8](repeating: 0, count: 64)
    )

    #expect(patched[9] == 100)
    #expect(patched[10] == 0) // 4 - min(4, 9)
    #expect(patched[25] == 100)
    #expect(patched[26] == 0) // 4 - min(4, 7)
}

@Test func parsesLiveFuncConfig() {
    // Captured from a real Ace 68 Turbo 16K with
    // `mchose-cli readraw 05 0 64`. The live device reports brightness as 100
    // (0x64), which matches the official web UI's 0..100 percent slider; the
    // earlier 0..4 note in the capture file was wrong.
    let live = Hex.parse(
        "50 00 AA BB 01 00 00 06 06 64 00 00 01 00 FF 00 00 00 64 FF 05 01 00 00 00 64 00 01 01 FF 00 00 64 00 00 06 00 0F 00 01 FF FF FF 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10"
    )!
    #expect(live.count == 64)

    guard let light = FuncConfigCodec.light(from: live) else {
        Issue.record("live func config did not decode")
        return
    }
    #expect(light.effect == 6)
    #expect(light.brightness == 100)
    #expect(light.speed == 4)
    #expect(light.customColorDisabled == 1)
    #expect(light.colorIndex == 0)
    #expect(light.hexColor == "#FF0000")
    #expect(light.sideEffect == 0)
    #expect(light.sideBrightness == 100)
    #expect(light.sideSpeed == 4)
    #expect(light.sideCustomColorDisabled == 1)
    #expect(light.sideHexColor == "#FF0000")

    // Patching the decoded values must leave the live bytes untouched.
    let patched = FuncConfigCodec.patch(light, into: live)
    #expect(Array(patched[8...16]) == Array(live[8...16]))
    #expect(Array(patched[24...31]) == Array(live[24...31]))
}

@Test func parsesBaseInfo() {
    // Live base capture: byte0 = slot 0, byte1 = 3 active profiles,
    // bytes 2..5 = identity order.
    let bytes: [UInt8] = [0, 3, 0, 1, 2, 3]
    let base = BaseCodec.parse(bytes)
    #expect(base?.slot == 0)
    #expect(base?.profileIndex == 0)
    #expect(base?.profileCount == 3)
    #expect(base?.profileOrder == [0, 1, 2, 3])

    // Logical profile 2 lives at order slot 2 with an identity order.
    let switched = BaseCodec.setProfileIndex(2, in: bytes)
    #expect(switched[0] == 2)
    #expect(switched[1] == 3)
}

@Test func parsesBaseInfoWithReorderedProfiles() {
    // order = [2, 0, 1, 3], active slot = 1 -> logical profile 0.
    let bytes: [UInt8] = [1, 3, 2, 0, 1, 3]
    let base = BaseCodec.parse(bytes)
    #expect(base?.slot == 1)
    #expect(base?.profileIndex == 0)
    #expect(base?.profileCount == 3)
    #expect(base?.profileOrder == [2, 0, 1, 3])

    // Logical profile 2 is at slot 0.
    let switched = BaseCodec.setProfileIndex(2, in: bytes)
    #expect(switched[0] == 0)
}

@Test func parsesBaseInfoFallbackWhenOrderIsInvalid() {
    // Non-permutation order: vendor decoder treats the slot as the index and
    // reports two profiles.
    let bytes: [UInt8] = [2, 3, 0, 1, 2, 2]
    let base = BaseCodec.parse(bytes)
    #expect(base?.profileIndex == 2)
    #expect(base?.profileCount == 2)
}
