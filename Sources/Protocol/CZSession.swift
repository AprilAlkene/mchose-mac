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
        timeout: TimeInterval = 1.0
    ) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: length)
        var page = 0

        while page < length {
            let size = min(CZCodec.maxDataLength, length - page)
            let request = codec.encodeGet(
                command: command,
                offset: offset + page,
                length: size
            )
            let response = try sendAndWait(
                request: request,
                command: command,
                reportId: reportId,
                timeout: timeout
            )

            for (index, byte) in response.payload.enumerated()
            where page + index < length {
                result[page + index] = byte
            }
            page += size
        }
        return result
    }

    public func write(
        command: UInt8,
        offset: Int,
        data: [UInt8],
        reportId: UInt8 = 0,
        timeout: TimeInterval = 1.0
    ) throws {
        guard !data.isEmpty else { return }

        var start = 0
        while start < data.count {
            var chunk = Array(
                data[start..<min(start + CZCodec.maxDataLength, data.count)]
            )
            var chunkOffset = offset + start

            if chunk.count < CZCodec.maxDataLength && start > 0 {
                chunkOffset = offset + data.count - CZCodec.maxDataLength
                chunk = Array(
                    data[(data.count - CZCodec.maxDataLength)..<data.count]
                )
            }

            let request = codec.encodeCommand(
                command: command,
                data: chunk,
                offset: chunkOffset
            )
            _ = try sendAndWait(
                request: request,
                command: command,
                reportId: reportId,
                timeout: timeout
            )
            start += CZCodec.maxDataLength
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
