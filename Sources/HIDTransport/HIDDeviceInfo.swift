import Foundation

public struct HIDDeviceInfo: Equatable, Sendable {
    public let product: String
    public let identity: HIDDeviceIdentity
    public let interface: HIDInterfaceDescriptor
    public let transport: String
    public let registryId: UInt64

    public init?(
        properties: [String: Any]
    ) {
        guard
            let product = properties["Product"] as? String,
            let vendorId = Self.intValue(properties["VendorID"]),
            let productId = Self.intValue(properties["ProductID"]),
            let usagePage = Self.intValue(properties["PrimaryUsagePage"]),
            let usage = Self.intValue(properties["PrimaryUsage"]),
            let maxInput = Self.intValue(properties["MaxInputReportSize"]),
            let maxOutput = Self.intValue(properties["MaxOutputReportSize"])
        else {
            return nil
        }

        self.product = product
        self.identity = HIDDeviceIdentity(vendorId: vendorId, productId: productId)
        self.interface = HIDInterfaceDescriptor(
            usagePage: usagePage,
            usage: usage,
            maxInputReportSize: maxInput,
            maxOutputReportSize: maxOutput
        )
        self.transport = properties["Transport"] as? String ?? "Unknown"
        self.registryId = Self.uint64Value(properties["RegistryID"]) ?? 0
    }

    public init(
        product: String,
        identity: HIDDeviceIdentity,
        interface: HIDInterfaceDescriptor,
        transport: String,
        registryId: UInt64
    ) {
        self.product = product
        self.identity = identity
        self.interface = interface
        self.transport = transport
        self.registryId = registryId
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func uint64Value(_ value: Any?) -> UInt64? {
        if let value = value as? UInt64 { return value }
        if let value = value as? NSNumber { return value.uint64Value }
        return nil
    }
}
