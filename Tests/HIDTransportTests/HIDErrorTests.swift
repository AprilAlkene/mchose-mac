import Testing
import IOKit
@testable import HIDTransport

@Test func notPermittedDescriptionContainsHexCode() {
    let error = HIDError.ioKit(kIOReturnNotPermitted)
    #expect(error.localizedDescription.contains("0xE00002E2"))
    #expect(error.localizedDescription.lowercased().contains("protected"))
}

@Test func notFoundDescription() {
    #expect(HIDError.notFound.localizedDescription == "MCHOSE configuration interface not found")
}
