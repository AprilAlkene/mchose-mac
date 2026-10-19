import Foundation

/// A point-in-time copy of every writable section of the device.
///
/// The snapshot stores decoded values instead of raw keymap bytes so that a
/// restore is not sensitive to the firmware's six-byte keymap stream
/// carry-over.
public struct DeviceSnapshot: Codable, Equatable, Sendable {
    public let product: String
    public let firmwareVersion: String?
    public let createdAt: Date
    /// 0-based profile the snapshot was taken from.
    public let profileIndex: Int
    public let triggers: [TriggerConfig]
    public let keymap: [KeyInfo]
    public let funcConfig: [UInt8]
    public let base: [UInt8]

    public init(
        product: String,
        firmwareVersion: String?,
        createdAt: Date,
        profileIndex: Int,
        triggers: [TriggerConfig],
        keymap: [KeyInfo],
        funcConfig: [UInt8],
        base: [UInt8]
    ) {
        self.product = product
        self.firmwareVersion = firmwareVersion
        self.createdAt = createdAt
        self.profileIndex = profileIndex
        self.triggers = triggers
        self.keymap = keymap
        self.funcConfig = funcConfig
        self.base = base
    }

    private enum CodingKeys: String, CodingKey {
        case product
        case firmwareVersion
        case createdAt
        case profileIndex
        case triggers
        case keymap
        case funcConfig
        case base
    }

    /// Snapshots written before `profileIndex` existed are treated as
    /// profile 0 snapshots.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        product = try container.decode(String.self, forKey: .product)
        firmwareVersion = try container.decodeIfPresent(
            String.self,
            forKey: .firmwareVersion
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        profileIndex = try container.decodeIfPresent(
            Int.self,
            forKey: .profileIndex
        ) ?? 0
        triggers = try container.decode(
            [TriggerConfig].self,
            forKey: .triggers
        )
        keymap = try container.decode([KeyInfo].self, forKey: .keymap)
        funcConfig = try container.decode([UInt8].self, forKey: .funcConfig)
        base = try container.decode([UInt8].self, forKey: .base)
    }
}

/// Reads and writes `DeviceSnapshot` files as JSON.
public enum SnapshotStore {
    public static func defaultDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("MCHOSE Mac", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
    }

    @discardableResult
    public static func save(
        _ snapshot: DeviceSnapshot,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = directory ?? defaultDirectory(fileManager: fileManager)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(fileName(for: snapshot.createdAt))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        return url
    }

    public static func load(from url: URL) throws -> DeviceSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DeviceSnapshot.self, from: data)
    }

    public static func write(
        _ snapshot: DeviceSnapshot,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    public static func latest(
        in directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL? {
        let directory = directory ?? defaultDirectory(fileManager: fileManager)
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { left, right in
                let leftDate = (try? left.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                let rightDate = (try? right.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
            .first
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "snapshot-\(formatter.string(from: date)).json"
    }
}
