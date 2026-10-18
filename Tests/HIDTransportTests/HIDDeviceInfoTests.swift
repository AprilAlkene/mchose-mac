import Testing
@testable import HIDTransport

@Test func mapsConfigurationInterfaceProperties() {
    let properties: [String: Any] = [
        "Product": "Ace 68 Turbo 16K",
        "VendorID": 0x3837,
        "ProductID": 0x3026,
        "PrimaryUsagePage": 0x01,
        "PrimaryUsage": 0x00,
        "MaxInputReportSize": 64,
        "MaxOutputReportSize": 64,
        "Transport": "USB",
        "RegistryID": 0x100004FD4 as UInt64,
    ]

    let info = HIDDeviceInfo(properties: properties)

    #expect(info?.product == "Ace 68 Turbo 16K")
    #expect(info?.identity.vendorId == 0x3837)
    #expect(info?.identity.productId == 0x3026)
    #expect(info?.interface.isConfigurationInterface == true)
    #expect(info?.transport == "USB")
    #expect(info?.registryId == 0x100004FD4)
}

@Test func rejectsIncompleteProperties() {
    let properties: [String: Any] = ["Product": "Ace 68 Turbo 16K"]
    #expect(HIDDeviceInfo(properties: properties) == nil)
}
