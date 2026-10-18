import Foundation
import Testing
@testable import Features
@testable import Protocol
@testable import HIDTransport

@Test func parsesBuildDateFromCapturedResponse() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tests/ProtocolTests/Fixtures/ace68-read-info.json")
    let data = try Data(contentsOf: url)
    let fixture = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let bytes = Hex.parse(fixture["responseHex"] as! String)!
    let response = try CZCodec().decodeResponse(bytes)

    let info = try DeviceInfoParser.parse(
        product: "Ace 68 Turbo 16K",
        response: response
    )

    #expect(info.product == "Ace 68 Turbo 16K")
    #expect(info.buildDate == "Jul 21 2026,15:16:19")
    #expect(info.firmwareVersion == "126")
    #expect(info.rffwVersion == "ffff")
    #expect(info.rawPayload.count == 27)
}
