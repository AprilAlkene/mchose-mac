/// Decoded 56-byte base struct (`0x04` read / `0x0E` write).
///
/// The layout below mirrors the vendor SDK's `Ne()` decoder:
///
/// ```text
/// byte 0     = slot index: order.indexOf(active profile)
/// byte 1     = number of active profiles
/// bytes 2..5 = profile order (a permutation of 0..<maxProfiles)
/// ...
/// ```
public struct BaseInfo: Equatable, Sendable {
    /// Raw slot written to byte 0.
    public var slot: Int
    /// Logical active profile index (`order[slot]` when the order is a
    /// permutation, otherwise `slot`).
    public var profileIndex: Int
    /// Number of active profiles (byte 1).
    public var profileCount: Int
    /// Profile order stored in bytes 2..5.
    public var profileOrder: [Int]

    public init(
        slot: Int,
        profileIndex: Int,
        profileCount: Int,
        profileOrder: [Int]
    ) {
        self.slot = slot
        self.profileIndex = profileIndex
        self.profileCount = profileCount
        self.profileOrder = profileOrder
    }
}

public enum BaseCodec {
    public static let length = 56
    /// Vendor SDK `MAX_KEYBOARD_PROFILE_LENGTH`.
    public static let maxProfiles = 4

    public static func parse(_ bytes: [UInt8]) -> BaseInfo? {
        guard bytes.count >= 2 + maxProfiles else { return nil }

        let slot = Int(bytes[0])
        let declaredCount = Int(bytes[1])
        let order = (0..<maxProfiles).map { Int(bytes[2 + $0]) }
        let isOrdered = order.sorted() == Array(0..<maxProfiles)
        let slotValid = slot >= 0 && slot < maxProfiles
        let countValid = !isOrdered || declaredCount <= maxProfiles
        let supported = slotValid && countValid

        let count: Int
        let profileIndex: Int
        if supported && isOrdered {
            count = max(1, min(declaredCount, maxProfiles))
            profileIndex = order[slot]
        } else if supported {
            count = 2
            profileIndex = slot
        } else {
            count = 1
            profileIndex = 0
        }

        return BaseInfo(
            slot: supported && isOrdered ? slot : 0,
            profileIndex: profileIndex,
            profileCount: count,
            profileOrder: isOrdered ? order : Array(0..<count)
        )
    }

    /// Writes the slot corresponding to `index` into byte 0, keeping the
    /// profile count and order untouched.
    public static func setProfileIndex(_ index: Int, in bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        guard result.isEmpty == false else { return result }

        let order = parse(result)?.profileOrder ?? Array(0..<maxProfiles)
        if let slot = order.firstIndex(of: index) {
            result[0] = UInt8(slot)
        } else {
            result[0] = UInt8(max(0, min(255, index)))
        }
        return result
    }
}
