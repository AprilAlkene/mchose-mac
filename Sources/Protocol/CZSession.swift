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

    public func getInfo(reportId: UInt8 = 0, timeout: TimeInterval = 2.0) throws -> CZResponse {
        let request = codec.encodeRequest(command: 0x03)
        var responseBytes: [UInt8] = []

        try handle.startInputReports { _, bytes in
            if bytes.count >= 2,
               bytes[0] == CZCodec.responseFlag,
               bytes[1] == 0x03,
               responseBytes.isEmpty {
                responseBytes = bytes
            }
        }
        defer { handle.stopInputReports() }

        let deadline = Date().addingTimeInterval(timeout)
        for _ in 0..<2 {
            try handle.setOutputReport(reportId: UInt32(reportId), bytes: request)
            let attemptDeadline = min(deadline, Date().addingTimeInterval(0.4))
            while responseBytes.isEmpty && Date() < attemptDeadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            if !responseBytes.isEmpty { break }
        }

        while responseBytes.isEmpty && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        guard !responseBytes.isEmpty else {
            throw CZSessionError.timeout
        }

        let response = try codec.decodeResponse(responseBytes)
        guard response.command == 0x03 else {
            throw CZSessionError.unexpectedCommand(response.command)
        }
        return response
    }
}
