import Testing
@testable import Protocol

@Test func timeoutDescription() {
    #expect(
        CZSessionError.timeout.localizedDescription
            == "Timed out waiting for a device response"
    )
}
