import Foundation
import HIDTransport
import Protocol

public enum DeviceConnectionError: Error, LocalizedError {
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "The device is not connected"
        }
    }
}

public final class DeviceConnection {
    public let ref: HIDDeviceRef
    public let manifest: DeviceManifest
    private var handle: HIDDeviceHandle?

    public init(ref: HIDDeviceRef, manifest: DeviceManifest) {
        self.ref = ref
        self.manifest = manifest
    }

    public func connect() throws {
        close()
        let handle = HIDDeviceHandle(device: ref.device)
        try handle.open()
        self.handle = handle
    }

    public func close() {
        handle?.close()
        handle = nil
    }

    public func readInfo() throws -> DeviceInfo {
        guard let handle else {
            throw DeviceConnectionError.notConnected
        }
        let session = CZSession(handle: handle)
        let response = try session.getInfo()
        return try DeviceInfoParser.parse(
            product: ref.info.product,
            response: response
        )
    }
}
