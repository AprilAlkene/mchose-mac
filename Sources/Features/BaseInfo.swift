public struct BaseInfo: Equatable, Sendable {
    public var profileIndex: Int
    public var profileCount: Int

    public init(profileIndex: Int, profileCount: Int) {
        self.profileIndex = profileIndex
        self.profileCount = profileCount
    }
}

public enum BaseCodec {
    public static let length = 56

    public static func parse(_ bytes: [UInt8]) -> BaseInfo? {
        guard bytes.count >= 2 else { return nil }
        return BaseInfo(
            profileIndex: Int(bytes[0]),
            profileCount: max(1, Int(bytes[1]) + 1)
        )
    }

    public static func setProfileIndex(_ index: Int, in bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        if !result.isEmpty {
            result[0] = UInt8(max(0, min(255, index)))
        }
        return result
    }
}
