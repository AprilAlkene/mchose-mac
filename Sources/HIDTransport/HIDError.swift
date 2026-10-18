import Foundation
import IOKit

public enum HIDError: Error, Equatable, LocalizedError {
    case notFound
    case openFailed(IOReturn)
    case ioKit(IOReturn)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "MCHOSE configuration interface not found"
        case .openFailed(let code), .ioKit(let code):
            let hex = String(format: "0x%08X", UInt32(bitPattern: code))
            if code == kIOReturnNotPermitted {
                return "IOKit error \(hex): interface is protected or permission is denied"
            }
            return "IOKit error \(hex)"
        case .invalidResponse:
            return "Invalid device response"
        }
    }
}
