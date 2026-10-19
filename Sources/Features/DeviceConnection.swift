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
    private var session: CZSession?

    public init(ref: HIDDeviceRef, manifest: DeviceManifest) {
        self.ref = ref
        self.manifest = manifest
    }

    public func connect() throws {
        close()
        let handle = HIDDeviceHandle(device: ref.device)
        try handle.open()
        self.handle = handle
        self.session = CZSession(handle: handle)
    }

    public func close() {
        session = nil
        handle?.close()
        handle = nil
    }

    private func requireSession() throws -> CZSession {
        guard let session else {
            throw DeviceConnectionError.notConnected
        }
        return session
    }

    public func readInfo() throws -> DeviceInfo {
        let session = try requireSession()
        let response = try session.getInfo()
        return try DeviceInfoParser.parse(
            product: ref.info.product,
            response: response
        )
    }

    public func readTriggers(profile: Int = 0) throws -> [TriggerConfig] {
        let session = try requireSession()
        let bytes = try session.read(
            command: 0xA0,
            offset: 1024 * profile,
            length: 1024
        )
        return TriggerCodec.unpack(bytes, maxKeys: 128)
    }

    public func writeTriggers(
        _ triggers: [TriggerConfig],
        profile: Int = 0
    ) throws {
        let session = try requireSession()
        try session.write(
            command: 0xA1,
            offset: 1024 * profile,
            data: TriggerCodec.pack(triggers)
        )
    }

    public func readKeymap(
        layer: Int = 0,
        profile: Int = 0,
        maxKeys: Int = 128,
        totalKeyAreaSize: Int = 384
    ) throws -> [KeyInfo] {
        let session = try requireSession()
        let bytes = try session.read(
            command: 0x08,
            offset: 0,
            length: totalKeyAreaSize
        )

        // The firmware's keymap stream can start with a 6-byte carry-over
        // from the previous page. A clean stream starts with the first key
        // (type 16); detect and drop the carry-over only in that case.
        var keyBytes = bytes
        if keyBytes.count >= 6,
           keyBytes[0] == 0x00,
           keyBytes[3] == 0x10 {
            keyBytes = Array(keyBytes.dropFirst(6))
        }

        if keyBytes.count < totalKeyAreaSize {
            keyBytes.append(
                contentsOf: Array(
                    repeating: 0xFF,
                    count: totalKeyAreaSize - keyBytes.count
                )
            )
        }
        return KeymapCodec.unpack(keyBytes, maxKeys: maxKeys)
    }

    public func writeKeymap(
        _ keys: [KeyInfo],
        layer: Int = 0,
        profile: Int = 0,
        totalKeyAreaSize: Int = 384
    ) throws {
        let session = try requireSession()
        let offset = totalKeyAreaSize * (4 * profile + layer)
        try session.write(
            command: 0x09,
            offset: offset,
            data: KeymapCodec.pack(keys),
            chunkSize: 54
        )
    }

    public func readFuncConfig(profile: Int = 0) throws -> [UInt8] {
        let session = try requireSession()
        return try session.read(
            command: 0x05,
            offset: 64 * profile,
            length: 64
        )
    }

    public func writeFuncConfig(
        _ bytes: [UInt8],
        profile: Int = 0
    ) throws {
        let session = try requireSession()
        try session.write(
            command: 0x06,
            offset: 64 * profile,
            data: bytes
        )
    }

    public func readLightConfig(profile: Int = 0) throws -> LightConfig? {
        FuncConfigCodec.light(from: try readFuncConfig(profile: profile))
    }

    public func writeLightConfig(
        _ light: LightConfig,
        profile: Int = 0
    ) throws {
        var bytes = try readFuncConfig(profile: profile)
        bytes = FuncConfigCodec.patch(light, into: bytes)
        try writeFuncConfig(bytes, profile: profile)
    }

    public func readBaseBytes() throws -> [UInt8] {
        let session = try requireSession()
        return try session.read(
            command: 0x04,
            offset: 0,
            length: 56
        )
    }

    public func readRaw(
        command: UInt8,
        offset: Int,
        length: Int
    ) throws -> [UInt8] {
        let session = try requireSession()
        return try session.read(
            command: command,
            offset: offset,
            length: length
        )
    }

    public func readBase() throws -> BaseInfo? {
        BaseCodec.parse(try readBaseBytes())
    }

    public func writeBase(_ bytes: [UInt8]) throws {
        let session = try requireSession()
        try session.write(
            command: 0x0E,
            offset: 0,
            data: bytes
        )
    }

    public func switchProfile(_ index: Int) throws {
        var bytes = try readBaseBytes()
        bytes = BaseCodec.setProfileIndex(index, in: bytes)
        try writeBase(bytes)
    }
}
