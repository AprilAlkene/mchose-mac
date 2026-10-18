import Foundation
import HIDTransport

public struct CZResponse: Equatable, Sendable {
    public let command: UInt8
    public let payloadLength: Int
    public let payloadOffset: Int
    public let payload: [UInt8]
    public let raw: [UInt8]

    public init(
        command: UInt8,
        payloadLength: Int,
        payloadOffset: Int,
        payload: [UInt8],
        raw: [UInt8]
    ) {
        self.command = command
        self.payloadLength = payloadLength
        self.payloadOffset = payloadOffset
        self.payload = payload
        self.raw = raw
    }
}

public struct CZCodec {
    public static let requestFlag: UInt8 = 0x55
    public static let responseFlag: UInt8 = 0xAA
    public static let reportLength = 64

    public init() {}

    public func encodeRequest(command: UInt8, payload: [UInt8] = []) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.reportLength)
        bytes[0] = Self.requestFlag
        bytes[1] = command
        bytes[2] = 0x00
        bytes[3] = 0x38
        bytes[4] = 0x38
        bytes[5] = 0x00
        bytes[6] = 0x00
        bytes[7] = 0x00

        let count = min(payload.count, Self.reportLength - 8)
        if count > 0 {
            bytes.replaceSubrange(8..<(8 + count), with: payload[0..<count])
        }
        return bytes
    }

    public func decodeResponse(_ bytes: [UInt8]) throws -> CZResponse {
        guard bytes.count >= 8, bytes[0] == Self.responseFlag else {
            throw HIDError.invalidResponse
        }

        let command = bytes[1]
        let payloadLength = Int(bytes[4])
        let payloadOffset = Int(bytes[5]) | (Int(bytes[6]) << 8)
        let start = 8 + payloadOffset

        guard start >= 8, payloadLength >= 0, start + payloadLength <= bytes.count else {
            throw HIDError.invalidResponse
        }

        return CZResponse(
            command: command,
            payloadLength: payloadLength,
            payloadOffset: payloadOffset,
            payload: Array(bytes[start..<(start + payloadLength)]),
            raw: bytes
        )
    }
}
