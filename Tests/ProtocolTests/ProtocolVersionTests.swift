import Testing
@testable import Protocol

@Test func protocolVersion() {
    #expect(ProtocolVersion.current == 1)
}
