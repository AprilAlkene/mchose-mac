import Testing
@testable import Features

@Test func packsCapturedFirstTrigger() {
    let trigger = TriggerConfig(
        switchType: 1,
        keyMode: 2,
        priority: 0,
        keyActuation: 135,
        pressPrecision: 1,
        releasePrecision: 1,
        rtPress: 300,
        rtRelease: 300,
        pressDeadzone: 0,
        releaseDeadzone: 0
    )

    #expect(
        TriggerCodec.pack([trigger])
            == [0xA1, 0x02, 0x86, 0x0A, 0x2B, 0x01, 0x2B, 0x01]
    )
}

@Test func triggerRoundTrip() {
    let trigger = TriggerConfig(
        switchType: 3,
        keyMode: 2,
        priority: 5,
        keyActuation: 120,
        pressPrecision: 2,
        releasePrecision: 1,
        rtPress: 280,
        rtRelease: 260,
        pressDeadzone: 3,
        releaseDeadzone: 4
    )

    let packed = TriggerCodec.pack([trigger])
    let unpacked = TriggerCodec.unpack(packed, maxKeys: 1)

    #expect(unpacked == [trigger])
}
