import Foundation
import Protocol

public enum DeviceInfoError: Error, LocalizedError {
    case incompletePayload

    public var errorDescription: String? {
        switch self {
        case .incompletePayload:
            return "getInfo payload is shorter than expected"
        }
    }
}

public enum DeviceInfoParser {
    public static func parse(
        product: String,
        response: CZResponse
    ) throws -> DeviceInfo {
        let payload = response.payload
        guard payload.count >= 27 else {
            throw DeviceInfoError.incompletePayload
        }

        let dateBytes = Array(payload.suffix(20))
        guard let buildDate = String(bytes: dateBytes, encoding: .utf8),
              buildDate.contains(":") else {
            throw DeviceInfoError.incompletePayload
        }

        let minor = String(format: "%02X", payload[0])
        let major = payload[1]
        let firmwareVersion = major == 0 ? minor : "\(major)\(minor)"

        let rffwValue = UInt16(payload[2]) | (UInt16(payload[3]) << 8)
        let rffwVersion = String(rffwValue, radix: 16)

        return DeviceInfo(
            product: product,
            buildDate: buildDate,
            firmwareVersion: firmwareVersion,
            rffwVersion: rffwVersion,
            collabType: nil,
            rawPayload: payload
        )
    }
}
