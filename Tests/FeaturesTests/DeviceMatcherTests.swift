import Foundation
import Testing
@testable import Features
@testable import HIDTransport

private func loadManifest() throws -> DeviceManifest {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/DeviceManifests/ace68_turbo_16k.json")
    return try ManifestLoader.load(from: url)
}

@Test func matchesVerifiedIdentity() throws {
    let manifest = try loadManifest()
    let info = HIDDeviceInfo(
        product: "Ace 68 Turbo 16K",
        identity: HIDDeviceIdentity(vendorId: 0x3837, productId: 0x3026),
        interface: HIDInterfaceDescriptor(
            usagePage: 1,
            usage: 0,
            maxInputReportSize: 64,
            maxOutputReportSize: 64
        ),
        transport: "USB",
        registryId: 1
    )

    #expect(DeviceMatcher.matches(info: info, manifest: manifest))
}

@Test func rejectsUnknownIdentity() throws {
    let manifest = try loadManifest()
    let info = HIDDeviceInfo(
        product: "Unknown",
        identity: HIDDeviceIdentity(vendorId: 0x1234, productId: 0x5678),
        interface: HIDInterfaceDescriptor(
            usagePage: 1,
            usage: 0,
            maxInputReportSize: 64,
            maxOutputReportSize: 64
        ),
        transport: "USB",
        registryId: 2
    )

    #expect(!DeviceMatcher.matches(info: info, manifest: manifest))
}
