import Testing
@testable import HIDTransport

@Test func normalConfigurationInterface() {
    let descriptor = HIDInterfaceDescriptor(
        usagePage: 0x01, usage: 0x00,
        maxInputReportSize: 64, maxOutputReportSize: 64
    )
    #expect(descriptor.isConfigurationInterface)
}

@Test func bootConfigurationInterface() {
    let descriptor = HIDInterfaceDescriptor(
        usagePage: 0xFF00, usage: 0x01,
        maxInputReportSize: 64, maxOutputReportSize: 64
    )
    #expect(descriptor.isConfigurationInterface)
}

@Test func keyboardInterfaceIsRejected() {
    let descriptor = HIDInterfaceDescriptor(
        usagePage: 0x01, usage: 0x06,
        maxInputReportSize: 16, maxOutputReportSize: 1
    )
    #expect(!descriptor.isConfigurationInterface)
}

@Test func smallVendorInterfaceIsRejected() {
    let descriptor = HIDInterfaceDescriptor(
        usagePage: 0x01, usage: 0x00,
        maxInputReportSize: 8, maxOutputReportSize: 1
    )
    #expect(!descriptor.isConfigurationInterface)
}
