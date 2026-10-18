public struct DeviceManifest: Codable, Equatable, Sendable {
    public struct Identity: Codable, Equatable, Sendable {
        public let vendorId: Int
        public let productId: Int
        public let mode: String

        public init(vendorId: Int, productId: Int, mode: String) {
            self.vendorId = vendorId
            self.productId = productId
            self.mode = mode
        }
    }

    public struct ConfigInterface: Codable, Equatable, Sendable {
        public let usagePage: Int
        public let usage: Int
        public let maxReportSize: Int

        public init(usagePage: Int, usage: Int, maxReportSize: Int) {
            self.usagePage = usagePage
            self.usage = usage
            self.maxReportSize = maxReportSize
        }
    }

    public struct Capabilities: Codable, Equatable, Sendable {
        public let magnetic: Bool
        public let keymap: Bool
        public let macros: Bool
        public let socd: Bool
        public let lighting: Bool
        public let perKeyLighting: Bool
        public let gifLighting: Bool
        public let musicSync: Bool
        public let battery: Bool

        public init(
            magnetic: Bool,
            keymap: Bool,
            macros: Bool,
            socd: Bool,
            lighting: Bool,
            perKeyLighting: Bool,
            gifLighting: Bool,
            musicSync: Bool,
            battery: Bool
        ) {
            self.magnetic = magnetic
            self.keymap = keymap
            self.macros = macros
            self.socd = socd
            self.lighting = lighting
            self.perKeyLighting = perKeyLighting
            self.gifLighting = gifLighting
            self.musicSync = musicSync
            self.battery = battery
        }
    }

    public let id: String
    public let displayName: String
    public let protocolFamily: String
    public let identities: [Identity]
    public let configInterface: ConfigInterface
    public let capabilities: Capabilities
    public let profileSlots: Int?
    public let macroSlots: Int?
    public let layoutAsset: String
    public let layoutId: String?
    public let verified: Bool
    public let firmwareVersion: Int?
    public let deviceType: Int?

    public init(
        id: String,
        displayName: String,
        protocolFamily: String,
        identities: [Identity],
        configInterface: ConfigInterface,
        capabilities: Capabilities,
        profileSlots: Int?,
        macroSlots: Int?,
        layoutAsset: String,
        layoutId: String?,
        verified: Bool,
        firmwareVersion: Int?,
        deviceType: Int?
    ) {
        self.id = id
        self.displayName = displayName
        self.protocolFamily = protocolFamily
        self.identities = identities
        self.configInterface = configInterface
        self.capabilities = capabilities
        self.profileSlots = profileSlots
        self.macroSlots = macroSlots
        self.layoutAsset = layoutAsset
        self.layoutId = layoutId
        self.verified = verified
        self.firmwareVersion = firmwareVersion
        self.deviceType = deviceType
    }
}
