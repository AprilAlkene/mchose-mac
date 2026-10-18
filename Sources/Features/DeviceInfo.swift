public struct DeviceInfo: Equatable, Sendable {
    public let product: String
    public let buildDate: String
    public let firmwareVersion: String?
    public let rffwVersion: String?
    public let collabType: UInt8?
    public let rawPayload: [UInt8]

    public init(
        product: String,
        buildDate: String,
        firmwareVersion: String?,
        rffwVersion: String?,
        collabType: UInt8?,
        rawPayload: [UInt8]
    ) {
        self.product = product
        self.buildDate = buildDate
        self.firmwareVersion = firmwareVersion
        self.rffwVersion = rffwVersion
        self.collabType = collabType
        self.rawPayload = rawPayload
    }
}
