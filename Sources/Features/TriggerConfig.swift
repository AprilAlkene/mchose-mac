public struct TriggerConfig: Codable, Equatable, Sendable {
    public var switchType: Int
    public var keyMode: Int
    public var priority: Int
    public var keyActuation: Int
    public var pressPrecision: Int
    public var releasePrecision: Int
    public var rtPress: Int
    public var rtRelease: Int
    public var pressDeadzone: Int
    public var releaseDeadzone: Int

    public init(
        switchType: Int = 0,
        keyMode: Int = 0,
        priority: Int = 0,
        keyActuation: Int = 135,
        pressPrecision: Int = 1,
        releasePrecision: Int = 1,
        rtPress: Int = 300,
        rtRelease: Int = 300,
        pressDeadzone: Int = 0,
        releaseDeadzone: Int = 0
    ) {
        self.switchType = switchType
        self.keyMode = keyMode
        self.priority = priority
        self.keyActuation = keyActuation
        self.pressPrecision = pressPrecision
        self.releasePrecision = releasePrecision
        self.rtPress = rtPress
        self.rtRelease = rtRelease
        self.pressDeadzone = pressDeadzone
        self.releaseDeadzone = releaseDeadzone
    }
}

public enum TriggerCodec {
    public static func pack(_ triggers: [TriggerConfig]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(triggers.count * 8)

        for trigger in triggers {
            var bytes = [UInt8](repeating: 0, count: 8)
            bytes[0] = UInt8(160 | (trigger.switchType & 15))
            bytes[1] = UInt8(
                ((trigger.priority & 15) << 4) | (trigger.keyMode & 15)
            )

            let actuation = max(0, trigger.keyActuation - 1)
            bytes[2] = UInt8(actuation & 0xFF)
            bytes[3] = UInt8((actuation >> 8) & 1)
                | UInt8((trigger.pressPrecision & 3) << 3)
                | UInt8((trigger.releasePrecision & 3) << 1)

            let press = max(0, trigger.rtPress - 1)
            bytes[4] = UInt8(press & 0xFF)
            bytes[5] = UInt8((press >> 8) & 1)
                | UInt8((max(0, trigger.pressDeadzone) & 0x7F) << 1)

            let release = max(0, trigger.rtRelease - 1)
            bytes[6] = UInt8(release & 0xFF)
            bytes[7] = UInt8((release >> 8) & 1)
                | UInt8((max(0, trigger.releaseDeadzone) & 0x7F) << 1)

            result.append(contentsOf: bytes)
        }
        return result
    }

    public static func unpack(_ bytes: [UInt8], maxKeys: Int) -> [TriggerConfig] {
        let count = min(maxKeys, bytes.count / 8)
        return (0..<count).map { index in
            let base = index * 8
            let b0 = bytes[base]
            let b1 = bytes[base + 1]
            let b3 = bytes[base + 3]
            let b5 = bytes[base + 5]
            let b7 = bytes[base + 7]

            return TriggerConfig(
                switchType: Int(b0 & 15),
                keyMode: Int(b1 & 15),
                priority: Int(b1 >> 4),
                keyActuation: (Int(bytes[base + 2]) | ((Int(b3) & 1) << 8)) + 1,
                pressPrecision: Int((b3 >> 3) & 3),
                releasePrecision: Int((b3 >> 1) & 3),
                rtPress: (Int(bytes[base + 4]) | ((Int(b5) & 1) << 8)) + 1,
                rtRelease: (Int(bytes[base + 6]) | ((Int(b7) & 1) << 8)) + 1,
                pressDeadzone: Int((b5 >> 1) & 0x7F),
                releaseDeadzone: Int((b7 >> 1) & 0x7F)
            )
        }
    }
}
