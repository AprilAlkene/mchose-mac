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
    let actual = CZCodec().encodeRequest(command: 0x03)
    #expect(actual == expected)
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
