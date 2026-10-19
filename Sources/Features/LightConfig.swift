import Foundation

public struct LightConfig: Equatable, Sendable {
    /// Light effect id, passed through to the firmware.
    public var effect: UInt8
    /// Main light brightness in percent, 0...100 (official web UI range).
    public var brightness: UInt8
    /// Main light speed, 0...4 (official web UI range, inverted on the wire).
    public var speed: UInt8
    public var direct: UInt8
    /// 1 = random color (vendor UI "随机色"), 0 = use the custom RGB values.
    public var customColorDisabled: UInt8
    public var colorIndex: UInt8
    public var hexColor: String
    public var sideEffect: UInt8
    /// Side light brightness in percent, 0...100.
    public var sideBrightness: UInt8
    /// Side light speed, 0...4 (inverted on the wire).
    public var sideSpeed: UInt8
    /// 1 = random color, 0 = use `sideHexColor`.
    public var sideCustomColorDisabled: UInt8
    public var sideHexColor: String

    public init(
        effect: UInt8 = 11,
        brightness: UInt8 = 100,
        speed: UInt8 = 2,
        direct: UInt8 = 0,
        customColorDisabled: UInt8 = 1,
        colorIndex: UInt8 = 0,
        hexColor: String = "#FF0000",
        sideEffect: UInt8 = 0,
        sideBrightness: UInt8 = 100,
        sideSpeed: UInt8 = 3,
        sideCustomColorDisabled: UInt8 = 1,
        sideHexColor: String = "#FF0000"
    ) {
        self.effect = effect
        self.brightness = brightness
        self.speed = speed
        self.direct = direct
        self.customColorDisabled = customColorDisabled
        self.colorIndex = colorIndex
        self.hexColor = hexColor
        self.sideEffect = sideEffect
        self.sideBrightness = sideBrightness
        self.sideSpeed = sideSpeed
        self.sideCustomColorDisabled = sideCustomColorDisabled
        self.sideHexColor = sideHexColor
    }
}

public enum FuncConfigCodec {
    public static let length = 64

    public static func light(from bytes: [UInt8]) -> LightConfig? {
        guard bytes.count >= 32 else { return nil }
        return LightConfig(
            effect: bytes[8],
            brightness: bytes[9],
            speed: UInt8(4 - min(4, Int(bytes[10]))),
            direct: bytes[11],
            customColorDisabled: bytes[12],
            colorIndex: bytes[13],
            hexColor: rgbHex(bytes[14], bytes[15], bytes[16]),
            sideEffect: bytes[24],
            sideBrightness: bytes[25],
            sideSpeed: UInt8(4 - min(4, Int(bytes[26]))),
            sideCustomColorDisabled: bytes[27],
            sideHexColor: rgbHex(bytes[29], bytes[30], bytes[31])
        )
    }

    public static func patch(_ light: LightConfig, into bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        if result.count < length {
            result.append(
                contentsOf: Array(repeating: 0, count: length - result.count)
            )
        }

        result[8] = light.effect
        result[9] = min(100, light.brightness)
        result[10] = UInt8(4 - min(4, Int(light.speed)))
        result[11] = light.direct
        result[12] = light.customColorDisabled
        result[13] = light.colorIndex

        let main = parseHex(light.hexColor)
        result[14] = main.0
        result[15] = main.1
        result[16] = main.2

        result[24] = light.sideEffect
        result[25] = min(100, light.sideBrightness)
        result[26] = UInt8(4 - min(4, Int(light.sideSpeed)))
        result[27] = light.sideCustomColorDisabled

        let side = parseHex(light.sideHexColor)
        result[29] = side.0
        result[30] = side.1
        result[31] = side.2

        return result
    }

    private static func rgbHex(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func parseHex(_ value: String) -> (UInt8, UInt8, UInt8) {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let number = UInt32(cleaned, radix: 16) else {
            return (0xFF, 0x00, 0x00)
        }
        return (
            UInt8((number >> 16) & 0xFF),
            UInt8((number >> 8) & 0xFF),
            UInt8(number & 0xFF)
        )
    }
}
