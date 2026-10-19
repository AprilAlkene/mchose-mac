import IOKit.hid
import Testing
@testable import HIDTransport

@Test func keepsOnlyConfigurationInterfaces() {
    let config = HIDInterfaceDescriptor(
        usagePage: 0x01, usage: 0x00,
        maxInputReportSize: 64, maxOutputReportSize: 64
    )
    let keyboard = HIDInterfaceDescriptor(
        usagePage: 0x01, usage: 0x06,
        maxInputReportSize: 16, maxOutputReportSize: 1
    )

    let infos = [
        HIDDeviceInfo(
            product: "Ace 68 Turbo 16K",
            identity: HIDDeviceIdentity(vendorId: 0x3837, productId: 0x3026),
            interface: config,
            transport: "USB",
            registryId: 0
        ),
        HIDDeviceInfo(
            product: "Ace 68 Turbo 16K",
            identity: HIDDeviceIdentity(vendorId: 0x3837, productId: 0x3026),
            interface: keyboard,
            transport: "USB",
            registryId: 1
        ),
    ]

    let result = HIDEnumerator.configurationInfos(from: infos)
    #expect(result.count == 1)
    #expect(result[0].interface.isConfigurationInterface)
}

@Test func matchingCoversBothConfigurationInterfaceFamilies() {
    let vendors = HIDDeviceIdentity.supportedVendorIds
    let entries = HIDEnumerator.configurationMatching
    #expect(entries.count == vendors.count * 2)

    for vendor in vendors {
        let families: Set<String> = Set(entries.compactMap { entry in
            guard entry[kIOHIDVendorIDKey as String] as? Int == vendor else { return nil }
            guard let page = entry[kIOHIDDeviceUsagePageKey as String] as? Int,
                  let usage = entry[kIOHIDDeviceUsageKey as String] as? Int else { return nil }
            return "\(page)/\(usage)"
        })
        #expect(families == ["\(0x01)/\(0x00)", "\(0xFF00)/\(0x01)"])
    }
}
