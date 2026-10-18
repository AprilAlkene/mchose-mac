import Testing
@testable import HIDTransport

@Test func supportedVendors() {
    #expect(HIDDeviceIdentity(vendorId: 0x3837, productId: 0x3026).isSupportedVendor)
    #expect(HIDDeviceIdentity(vendorId: 0x19F5, productId: 0xFC30).isSupportedVendor)
    #expect(HIDDeviceIdentity(vendorId: 0x41E4, productId: 0x2102).isSupportedVendor)
}

@Test func unknownVendor() {
    #expect(!HIDDeviceIdentity(vendorId: 0x1234, productId: 0x5678).isSupportedVendor)
}
