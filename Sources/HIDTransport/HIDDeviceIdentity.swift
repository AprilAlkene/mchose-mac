public struct HIDDeviceIdentity: Equatable, Sendable {
    public let vendorId: Int
    public let productId: Int

    public init(vendorId: Int, productId: Int) {
        self.vendorId = vendorId
        self.productId = productId
    }

    public static let supportedVendorIds: Set<Int> = [0x19F5, 0x3837, 0x41E4]

    public var isSupportedVendor: Bool {
        Self.supportedVendorIds.contains(vendorId)
    }
}
