import Foundation
import Testing
@testable import Protocol
@testable import HIDTransport

private func loadFixture() throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/ace68-read-info.json")
    let data = try Data(contentsOf: url)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

@Test func encodesCapturedGetInfoRequest() throws {
    let fixture = try loadFixture()
    let expected = Hex.parse(fixture["requestHex"] as! String)!
    let actual = CZCodec().encodeGet(command: 0x03, offset: 0, length: 56)
    #expect(actual == expected)
}

@Test func encodesCommandWithSumChecksum() {
    let packet = CZCodec().encodeCommand(
        command: 0x2A,
        data: [0x01, 0x02, 0x03],
        offset: 0
    )
    let expected: [UInt8] = [
        0x55, 0x2A, 0x00, 0x09, 0x03, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03,
    ] + Array(repeating: 0, count: 53)
    #expect(packet == expected)
}

@Test func encodesOffsetLittleEndian() {
    let packet = CZCodec().encodeGet(command: 0xA0, offset: 512, length: 56)
    #expect(packet[4] == 56)
    #expect(packet[5] == 0x00)
    #expect(packet[6] == 0x02)
    #expect(packet[3] == 0x3A)
}

@Test func decodesCapturedResponse() throws {
    let fixture = try loadFixture()
    let bytes = Hex.parse(fixture["responseHex"] as! String)!
    let response = try CZCodec().decodeResponse(bytes)

    #expect(response.command == 0x03)
    #expect(response.payloadLength == 27)
    #expect(response.payloadOffset == 0)
    #expect(Hex.string(response.payload) == fixture["responsePayloadHex"] as! String)
}

@Test func decodesFirmwareBuildDate() throws {
    let fixture = try loadFixture()
    let bytes = Hex.parse(fixture["responseHex"] as! String)!
    let response = try CZCodec().decodeResponse(bytes)
    let dateBytes = Array(response.payload.suffix(20))
    let date = String(bytes: dateBytes, encoding: .utf8)

    #expect(date == fixture["buildDate"] as! String)
}

@Test func rejectsWrongResponseFlag() {
    #expect(throws: HIDError.self) {
        try CZCodec().decodeResponse([0x55, 0x03, 0, 0, 0, 0, 0, 0])
    }
}
