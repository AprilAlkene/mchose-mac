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

/// Controls whether a connection is allowed to modify the device.
public enum DeviceWritePolicy: Equatable, Sendable {
    /// Reads and writes are allowed.
    case allow
    /// Only read commands are sent; every write throws
    /// `DeviceWriteError.readOnlyBlocked`.
    case readOnly
    /// Writes are encoded and validated but never sent to the device.
    case dryRun
}

public enum DeviceWriteError: Error, Equatable, LocalizedError {
    case readOnlyBlocked
    case verificationFailed(feature: String)

    public var errorDescription: String? {
        switch self {
        case .readOnlyBlocked:
            return "Read-only mode is enabled; no write command was sent"
        case .verificationFailed(let feature):
            return "Readback verification failed for \(feature); the previous state was restored when possible"
        }
    }
}

public final class DeviceConnection {
    public let ref: HIDDeviceRef
    public let manifest: DeviceManifest

    /// Safety policy for this connection. Defaults to `.allow` so that the
    /// caller (CLI or app) has to opt *out* of writing explicitly.
    public var writePolicy: DeviceWritePolicy = .allow {
        didSet { session?.isDryRun = writePolicy == .dryRun }
    }

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
        let session = CZSession(handle: handle)
        session.isDryRun = writePolicy == .dryRun
        self.session = session
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

    private func ensureWriteAllowed() throws {
        if writePolicy == .readOnly {
            throw DeviceWriteError.readOnlyBlocked
        }
    }

    // MARK: - Reads

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
            offset: DeviceMemoryMap.triggerOffset(profile: profile),
            length: DeviceMemoryMap.triggerAreaSize
        )
        return TriggerCodec.unpack(bytes, maxKeys: 128)
    }

    public func readKeymap(
        layer: Int = 0,
        profile: Int = 0,
        maxKeys: Int = 128
    ) throws -> [KeyInfo] {
        let session = try requireSession()
        // Addressed pages start exactly at the requested area, so the payload
        // is the keymap itself. (The old "six-byte carry-over" hack was needed
        // when every page was requested with offset 0; a read of all 16
        // profile/layer areas on hardware starts with key type 0x10 each time.)
        let bytes = try session.read(
            command: 0x08,
            offset: DeviceMemoryMap.keymapOffset(profile: profile, layer: layer),
            length: DeviceMemoryMap.usedKeyAreaSize
        )
        return KeymapCodec.unpack(bytes, maxKeys: maxKeys)
    }

    public func readFuncConfig(profile: Int = 0) throws -> [UInt8] {
        let session = try requireSession()
        return try session.read(
            command: 0x05,
            offset: DeviceMemoryMap.funcConfigOffset(profile: profile),
            length: DeviceMemoryMap.funcConfigSize
        )
    }

    public func readLightConfig(profile: Int = 0) throws -> LightConfig? {
        FuncConfigCodec.light(from: try readFuncConfig(profile: profile))
    }

    public func readBaseBytes() throws -> [UInt8] {
        let session = try requireSession()
        return try session.read(
            command: 0x04,
            offset: 0,
            length: DeviceMemoryMap.baseSize
        )
    }

    public func readBase() throws -> BaseInfo? {
        BaseCodec.parse(try readBaseBytes())
    }

    /// Reads the whole writable state of the currently active profile.
    public func readActiveProfile() throws -> (profile: Int, base: BaseInfo?) {
        let base = try readBase()
        return (base?.profileIndex ?? 0, base)
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

    // MARK: - Raw writes

    public func writeRaw(
        command: UInt8,
        offset: Int,
        data: [UInt8],
        chunkSize: Int = CZCodec.maxDataLength
    ) throws {
        try ensureWriteAllowed()
        let session = try requireSession()
        try session.write(
            command: command,
            offset: offset,
            data: data,
            chunkSize: chunkSize
        )
    }

    // MARK: - Writes

    public func writeTriggers(
        _ triggers: [TriggerConfig],
        profile: Int = 0
    ) throws {
        try ensureWriteAllowed()
        let session = try requireSession()
        try session.write(
            command: 0xA1,
            offset: DeviceMemoryMap.triggerOffset(profile: profile),
            data: TriggerCodec.pack(triggers)
        )
    }

    public func writeKeymap(
        _ keys: [KeyInfo],
        layer: Int = 0,
        profile: Int = 0
    ) throws {
        try ensureWriteAllowed()
        let session = try requireSession()
        try session.write(
            command: 0x09,
            offset: DeviceMemoryMap.keymapOffset(profile: profile, layer: layer),
            data: KeymapCodec.pack(keys),
            chunkSize: 54
        )
    }

    public func writeFuncConfig(
        _ bytes: [UInt8],
        profile: Int = 0
    ) throws {
        try ensureWriteAllowed()
        let session = try requireSession()
        try session.write(
            command: 0x06,
            offset: DeviceMemoryMap.funcConfigOffset(profile: profile),
            data: bytes
        )
    }

    public func writeLightConfig(
        _ light: LightConfig,
        profile: Int = 0
    ) throws {
        try ensureWriteAllowed()
        let bytes = try readFuncConfig(profile: profile)
        try writeFuncConfig(
            FuncConfigCodec.patch(light, into: bytes),
            profile: profile
        )
    }

    public func writeBase(_ bytes: [UInt8]) throws {
        try ensureWriteAllowed()
        let session = try requireSession()
        try session.write(
            command: 0x0E,
            offset: 0,
            data: bytes
        )
    }

    // MARK: - Applying changes with readback verification

    /// Writes the trigger settings and verifies them by reading them back.
    /// If the readback does not match, the previous values are written back
    /// before the failure is reported.
    public func applyTriggers(
        _ triggers: [TriggerConfig],
        profile: Int = 0
    ) throws {
        try ensureWriteAllowed()
        guard writePolicy == .allow else {
            // Dry run: encode to surface payload errors, but never touch the device.
            _ = TriggerCodec.pack(triggers)
            return
        }

        let previous = try readTriggers(profile: profile)
        try writeTriggers(triggers, profile: profile)
        do {
            let readback = try readTriggers(profile: profile)
            guard readback == triggers else {
                try? writeTriggers(previous, profile: profile)
                throw DeviceWriteError.verificationFailed(feature: "magnetic trigger settings")
            }
        } catch let error as DeviceWriteError {
            throw error
        } catch {
            try? writeTriggers(previous, profile: profile)
            throw error
        }
    }

    /// Writes the keymap and verifies it by reading it back. Restores the
    /// previous keymap when the readback does not match.
    public func applyKeymap(
        _ keys: [KeyInfo],
        layer: Int = 0,
        profile: Int = 0
    ) throws {
        try ensureWriteAllowed()
        guard writePolicy == .allow else {
            _ = KeymapCodec.pack(keys)
            return
        }

        let previous = try readKeymap(layer: layer, profile: profile)
        try writeKeymap(keys, layer: layer, profile: profile)
        do {
            let readback = try readKeymap(layer: layer, profile: profile)
            guard readback == keys else {
                try? writeKeymap(previous, layer: layer, profile: profile)
                throw DeviceWriteError.verificationFailed(feature: "keymap")
            }
        } catch let error as DeviceWriteError {
            throw error
        } catch {
            try? writeKeymap(previous, layer: layer, profile: profile)
            throw error
        }
    }

    /// Patches the light fields of the func config, verifies the readback and
    /// restores the previous func config when the device does not echo the new
    /// values.
    public func applyLightConfig(
        _ light: LightConfig,
        profile: Int = 0
    ) throws {
        try ensureWriteAllowed()
        guard writePolicy == .allow else {
            _ = FuncConfigCodec.light(from: try readFuncConfig(profile: profile))
            return
        }

        let previous = try readFuncConfig(profile: profile)
        try writeFuncConfig(
            FuncConfigCodec.patch(light, into: previous),
            profile: profile
        )
        do {
            let readback = try readFuncConfig(profile: profile)
            guard FuncConfigCodec.light(from: readback) == light else {
                try? writeFuncConfig(previous, profile: profile)
                throw DeviceWriteError.verificationFailed(feature: "lighting")
            }
        } catch let error as DeviceWriteError {
            throw error
        } catch {
            try? writeFuncConfig(previous, profile: profile)
            throw error
        }
    }

    public func switchProfile(_ index: Int) throws {
        try ensureWriteAllowed()
        if writePolicy == .dryRun {
            return
        }

        let previous = try readBaseBytes()
        let updated = BaseCodec.setProfileIndex(index, in: previous)
        try writeBase(updated)
        do {
            guard let base = try readBase(), base.profileIndex == index else {
                try? writeBase(previous)
                throw DeviceWriteError.verificationFailed(feature: "profile switch")
            }
        } catch let error as DeviceWriteError {
            throw error
        } catch {
            try? writeBase(previous)
            throw error
        }
    }

    // MARK: - Snapshots

    /// Captures the writable state of the currently active profile so that it
    /// can be restored later with `restore(_:)`.
    public func captureSnapshot() throws -> DeviceSnapshot {
        let info = try? readInfo()
        let base = try readBaseBytes()
        let profile = BaseCodec.parse(base)?.profileIndex ?? 0
        return DeviceSnapshot(
            product: ref.info.product,
            firmwareVersion: info?.firmwareVersion,
            createdAt: Date(),
            profileIndex: profile,
            triggers: try readTriggers(profile: profile),
            keymap: try readKeymap(profile: profile),
            funcConfig: try readFuncConfig(profile: profile),
            base: base
        )
    }

    /// Writes a snapshot back to the profile it was captured from and verifies
    /// every section. The base struct is restored last so that the active
    /// profile ends up where it was when the snapshot was taken.
    public func restore(_ snapshot: DeviceSnapshot) throws {
        try ensureWriteAllowed()
        guard writePolicy == .allow else {
            return
        }

        let profile = snapshot.profileIndex

        try writeTriggers(snapshot.triggers, profile: profile)
        guard try readTriggers(profile: profile) == snapshot.triggers else {
            throw DeviceWriteError.verificationFailed(feature: "snapshot triggers")
        }

        try writeKeymap(snapshot.keymap, profile: profile)
        guard try readKeymap(profile: profile) == snapshot.keymap else {
            throw DeviceWriteError.verificationFailed(feature: "snapshot keymap")
        }

        try writeFuncConfig(snapshot.funcConfig, profile: profile)
        guard try readFuncConfig(profile: profile) == snapshot.funcConfig else {
            throw DeviceWriteError.verificationFailed(feature: "snapshot func config")
        }

        try writeBase(snapshot.base)
        guard try readBaseBytes() == snapshot.base else {
            throw DeviceWriteError.verificationFailed(feature: "snapshot base")
        }
    }
}
