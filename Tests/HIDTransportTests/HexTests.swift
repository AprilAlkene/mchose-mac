import Testing
@testable import HIDTransport

@Test func hexFormat() {
    #expect(Hex.string([0x00, 0x0A, 0xFF]) == "00 0A FF")
}

@Test func hexParse() {
    #expect(Hex.parse("00 0a ff") == [0x00, 0x0A, 0xFF])
}

@Test func hexParseRejectsOddLength() {
    #expect(Hex.parse("0A F") == nil)
}
