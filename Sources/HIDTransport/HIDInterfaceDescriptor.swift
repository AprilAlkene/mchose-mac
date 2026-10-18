public struct HIDInterfaceDescriptor: Equatable, Sendable {
    public let usagePage: Int
    public let usage: Int
    public let maxInputReportSize: Int
    public let maxOutputReportSize: Int

    public init(
        usagePage: Int,
        usage: Int,
        maxInputReportSize: Int,
        maxOutputReportSize: Int
    ) {
        self.usagePage = usagePage
        self.usage = usage
        self.maxInputReportSize = maxInputReportSize
        self.maxOutputReportSize = maxOutputReportSize
    }

    public var isConfigurationInterface: Bool {
        let isNormal = usagePage == 0x01 && usage == 0x00
        let isBoot = usagePage == 0xFF00 && usage == 0x01
        return (isNormal || isBoot) && maxOutputReportSize >= 32
    }
}
