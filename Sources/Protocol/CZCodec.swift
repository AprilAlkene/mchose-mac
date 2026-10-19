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
    public static let maxDataLength = 56

    public init() {}

    public func encodeGet(
        command: UInt8,
        offset: Int,
        length: Int
    ) -> [UInt8] {
        encodePacket(
            command: command,
            data: [],
            declaredLength: min(length, Self.maxDataLength),
            offset: offset
        )
    }

    public func encodeCommand(
        command: UInt8,
        data: [UInt8],
        offset: Int
    ) -> [UInt8] {
        let clipped = Array(data.prefix(Self.maxDataLength))
        return encodePacket(
            command: command,
            data: clipped,
            declaredLength: clipped.count,
            offset: offset
        )
    }

    private func encodePacket(
        command: UInt8,
        data: [UInt8],
        declaredLength: Int,
        offset: Int
    ) -> [UInt8] {
        var header: [UInt8] = [
            UInt8(declaredLength & 0xFF),
            UInt8(offset & 0xFF),
            UInt8((offset >> 8) & 0xFF),
            0,
        ]
        header.append(contentsOf: data)

        let checksum = UInt8(header.reduce(0) { $0 + Int($1) } & 0xFF)
        var packet: [UInt8] = [Self.requestFlag, command, 0, checksum]
        packet.append(contentsOf: header)

        if packet.count < Self.reportLength {
            packet.append(
                contentsOf: Array(repeating: 0, count: Self.reportLength - packet.count)
            )
        }
        return Array(packet.prefix(Self.reportLength))
    }

    public func decodeResponse(_ bytes: [UInt8]) throws -> CZResponse {
        guard bytes.count >= 8, bytes[0] == Self.responseFlag else {
            throw HIDError.invalidResponse
        }

        let command = bytes[1]
        let payloadLength = Int(bytes[4])
        let payloadOffset = Int(bytes[5]) | (Int(bytes[6]) << 8)
        let start = 8

        guard payloadLength >= 0, start + payloadLength <= bytes.count else {
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
