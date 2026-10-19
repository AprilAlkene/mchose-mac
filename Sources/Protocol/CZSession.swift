import Foundation
import HIDTransport

public enum CZSessionError: Error, Equatable, LocalizedError {
    case timeout
    case unexpectedCommand(UInt8)

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Timed out waiting for a device response"
        case .unexpectedCommand(let command):
            return String(format: "Unexpected response command 0x%02X", command)
        }
    }
}

public final class CZSession {
    private let handle: HIDDeviceHandle
    private let codec: CZCodec

    public init(handle: HIDDeviceHandle, codec: CZCodec = CZCodec()) {
        self.handle = handle
        self.codec = codec
    }

    public func getInfo(
        reportId: UInt8 = 0,
        timeout: TimeInterval = 2.0
    ) throws -> CZResponse {
        let request = codec.encodeGet(command: 0x03, offset: 0, length: 56)
        return try sendAndWait(
            request: request,
            command: 0x03,
            reportId: reportId,
            timeout: timeout
        )
    }

    public func read(
        command: UInt8,
        offset: Int,
        length: Int,
        reportId: UInt8 = 0,
        timeout: TimeInterval = 3.0
    ) throws -> [UInt8] {
        guard length > 0 else { return [] }

        let pageCount = (length + CZCodec.maxDataLength - 1)
            / CZCodec.maxDataLength
        var responses: [CZResponse] = []

        try handle.startInputReports { _, bytes in
            guard bytes.count >= 2,
                  bytes[0] == CZCodec.responseFlag,
                  bytes[1] == command else {
                return
            }
            if let response = try? self.codec.decodeResponse(bytes) {
                responses.append(response)
            }
        }
        defer { handle.stopInputReports() }

        for page in 0..<pageCount {
            let pageStart = page * CZCodec.maxDataLength
            let size = min(CZCodec.maxDataLength, length - pageStart)
            // Commands 8/0xA0 stream chunks and require offset 0; command 5
            // (func config) is addressed and needs the page offset.
            let requestOffset = command == 0x05 ? offset + pageStart : 0
            let request = codec.encodeGet(
                command: command,
                offset: requestOffset,
                length: size
            )
            try handle.setOutputReport(
                reportId: UInt32(reportId),
                bytes: request
            )
            Thread.sleep(forTimeInterval: 0.002)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while responses.count < pageCount && Date() < deadline {
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }

        guard responses.count >= pageCount else {
            throw CZSessionError.timeout
        }

        var result: [UInt8] = []
        result.reserveCapacity(length)
        for response in responses.prefix(pageCount) {
            result.append(contentsOf: response.payload)
            if result.count >= length { break }
        }

        if result.count < length {
            result.append(
                contentsOf: Array(repeating: 0, count: length - result.count)
            )
        }
        return Array(result.prefix(length))
    }

    public func write(
        command: UInt8,
        offset: Int,
        data: [UInt8],
        chunkSize: Int = CZCodec.maxDataLength,
        reportId: UInt8 = 0,
        timeout: TimeInterval = 3.0
    ) throws {
        guard !data.isEmpty else { return }

        let effectiveChunkSize = max(1, min(chunkSize, CZCodec.maxDataLength))
        var packets: [[UInt8]] = []
        var start = 0
        while start < data.count {
            var chunk = Array(
                data[start..<min(start + effectiveChunkSize, data.count)]
            )
            var chunkOffset = offset + start

            if chunk.count < effectiveChunkSize && start > 0 {
                chunkOffset = offset + data.count - effectiveChunkSize
                chunk = Array(
                    data[(data.count - effectiveChunkSize)..<data.count]
                )
            }

            packets.append(
                codec.encodeCommand(
                    command: command,
                    data: chunk,
                    offset: chunkOffset
                )
            )
            start += effectiveChunkSize
        }

        var responseCount = 0
        try handle.startInputReports { _, bytes in
            guard bytes.count >= 2,
                  bytes[0] == CZCodec.responseFlag,
                  bytes[1] == command else {
                return
            }
            responseCount += 1
        }
        defer { handle.stopInputReports() }

        for packet in packets {
            try handle.setOutputReport(
                reportId: UInt32(reportId),
                bytes: packet
            )
            Thread.sleep(forTimeInterval: 0.002)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while responseCount < packets.count && Date() < deadline {
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }

        guard responseCount > 0 else {
            throw CZSessionError.timeout
        }
    }

    private func sendAndWait(
        request: [UInt8],
        command: UInt8,
        reportId: UInt8,
        timeout: TimeInterval
    ) throws -> CZResponse {
        var response: CZResponse?

        try handle.startInputReports { _, bytes in
            guard response == nil,
                  bytes.count >= 2,
                  bytes[0] == CZCodec.responseFlag,
                  bytes[1] == command else {
                return
            }
            response = try? self.codec.decodeResponse(bytes)
        }
        defer { handle.stopInputReports() }

        try handle.setOutputReport(reportId: UInt32(reportId), bytes: request)

        let deadline = Date().addingTimeInterval(timeout)
        while response == nil && Date() < deadline {
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }

        guard let response else {
            throw CZSessionError.timeout
        }
        return response
    }
}
