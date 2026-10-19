import Foundation
import Combine
import AppKit
import OSLog
import HIDTransport
import Features

private let logger = Logger(subsystem: "local.mchose.mac", category: "device")

struct ConnectedDevice: Identifiable {
    let id: String
    let ref: HIDDeviceRef
    let connection: DeviceConnection

    init(ref: HIDDeviceRef, manifest: DeviceManifest) {
        self.id = "\(ref.info.identity.vendorId)-\(ref.info.identity.productId)-\(ref.info.registryId)"
        self.ref = ref
        self.connection = DeviceConnection(ref: ref, manifest: manifest)
    }
}

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [ConnectedDevice] = []
    @Published private(set) var selected: ConnectedDevice?
    @Published private(set) var info: DeviceInfo?
    @Published private(set) var triggers: [TriggerConfig] = []
    @Published private(set) var keymap: [KeyInfo] = []
    @Published private(set) var light: LightConfig?
    @Published private(set) var base: BaseInfo?
    @Published private(set) var status: String = "未连接"
    @Published private(set) var error: String?
    @Published private(set) var isBusy = false
    @Published private(set) var writePolicy: DeviceWritePolicy = .allow
    @Published private(set) var lastSnapshotURL: URL?

    let switcher = ProfileSwitcher.shared

    private let manifest: DeviceManifest?
    private let enumerator = HIDEnumerator()

    var canWrite: Bool {
        writePolicy != .readOnly
    }

    var policyLabel: String {
        switch writePolicy {
        case .allow:
            return "可写"
        case .readOnly:
            return "只读模式（启动时加 --read-only）"
        case .dryRun:
            return "dry-run（只编码，不写入）"
        }
    }

    init() {
        manifest = try? ManifestLoader.loadBundled()
        writePolicy = Self.writePolicyFromCommandLine()
        switcher.onSwitch = { [weak self] index in
            self?.switchProfile(index)
        }
        switcher.start()
        logger.info(
            "manifest loaded: \(self.manifest?.displayName ?? "none", privacy: .public) policy=\(String(describing: self.writePolicy), privacy: .public)"
        )
    }

    private static func writePolicyFromCommandLine() -> DeviceWritePolicy {
        let arguments = CommandLine.arguments
        if arguments.contains("--read-only") {
            return .readOnly
        }
        if arguments.contains("--dry-run") {
            return .dryRun
        }
        return .allow
    }

    func refresh() {
        error = nil
        guard let manifest else {
            status = "设备清单加载失败"
            return
        }

        let refs = enumerator.listDevices().filter {
            DeviceMatcher.matches(info: $0.info, manifest: manifest)
                && $0.info.interface.isConfigurationInterface
        }

        devices = refs.map { ConnectedDevice(ref: $0, manifest: manifest) }
        applyWritePolicy()
        if selected == nil {
            selected = devices.first
        }
        status = devices.isEmpty ? "未连接" : "已发现 \(devices.count) 个设备"
        logger.info("scan complete: \(self.devices.count) device(s)")

        if let first = devices.first, info == nil {
            selected = first
            connectSelected()
        }
    }

    private func applyWritePolicy() {
        for device in devices {
            device.connection.writePolicy = writePolicy
        }
        selected?.connection.writePolicy = writePolicy
    }

    func select(_ device: ConnectedDevice) {
        selected = device
        applyWritePolicy()
        info = nil
        triggers = []
        keymap = []
        light = nil
        base = nil
    }

    func connectSelected() {
        guard let selected else { return }
        selected.connection.writePolicy = writePolicy
        do {
            try selected.connection.connect()
            info = try selected.connection.readInfo()
            loadFeatures()
            status = "已连接"
            error = nil
            if let info {
                logger.info(
                    "connected \(info.product, privacy: .public) firmware \(info.firmwareVersion ?? "unknown", privacy: .public) build \(info.buildDate, privacy: .public)"
                )
            }
        } catch {
            status = "连接失败"
            self.error = error.localizedDescription
            info = nil
            logger.error("connect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disconnectSelected() {
        selected?.connection.close()
        info = nil
        triggers = []
        keymap = []
        light = nil
        base = nil
        status = "未连接"
    }

    // MARK: - Applying changes

    func applyTriggers(_ updated: [TriggerConfig]) {
        perform {
            let connection = try self.requireConnection()
            let profile = self.base?.profileIndex ?? 0
            try connection.applyTriggers(updated, profile: profile)
            self.triggers = try connection.readTriggers(profile: profile)
            self.status = self.applyStatus("磁轴")
        }
    }

    func applyKeymap(_ updated: [KeyInfo]) {
        perform {
            let connection = try self.requireConnection()
            let profile = self.base?.profileIndex ?? 0
            try connection.applyKeymap(updated, profile: profile)
            self.keymap = try connection.readKeymap(profile: profile)
            self.status = self.applyStatus("键位")
        }
    }

    func applyLight(_ updated: LightConfig) {
        perform {
            let connection = try self.requireConnection()
            let profile = self.base?.profileIndex ?? 0
            try connection.applyLightConfig(updated, profile: profile)
            self.light = try connection.readLightConfig(profile: profile)
            self.status = self.applyStatus("灯效")
        }
    }

    func switchProfile(_ index: Int) {
        guard canWrite else {
            status = "只读模式，未切换配置档"
            return
        }
        if let base, base.profileIndex == index {
            status = "已在配置档 \(index + 1)"
            return
        }
        perform(snapshot: false) {
            let connection = try self.requireConnection()
            try connection.switchProfile(index)
            self.base = try connection.readBase()
            self.loadFeatures(profile: index)
            self.status = self.writePolicy == .dryRun
                ? "配置档切换已编码（dry-run，未写入）"
                : "已切换到配置档 \(index + 1)"
        }
    }

    func restoreLastSnapshot() {
        guard selected != nil else { return }
        guard canWrite else {
            error = "只读模式，未恢复快照"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try resolveSnapshotURL()
            let snapshot = try SnapshotStore.load(from: url)
            try selected?.connection.restore(snapshot)
            info = try selected?.connection.readInfo()
            loadFeatures()
            lastSnapshotURL = url
            error = nil
            status = writePolicy == .dryRun
                ? "dry-run：快照已校验，未写入"
                : "已恢复快照 \(url.lastPathComponent)"
        } catch {
            status = "恢复失败"
            self.error = error.localizedDescription
            logger.error("restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func resolveSnapshotURL() throws -> URL {
        if let lastSnapshotURL {
            return lastSnapshotURL
        }
        if let latest = try SnapshotStore.latest() {
            return latest
        }
        throw SnapshotError.noSnapshot
    }

    private func applyStatus(_ feature: String) -> String {
        switch writePolicy {
        case .allow:
            return "\(feature)已应用并回读校验"
        case .dryRun:
            return "\(feature)已编码（dry-run，未写入）"
        case .readOnly:
            return "只读模式，未写入"
        }
    }

    private func requireConnection() throws -> DeviceConnection {
        guard let selected else {
            throw DeviceConnectionError.notConnected
        }
        return selected.connection
    }

    // MARK: - Reading

    /// Loads base first, then reads the keymap/trigger/lighting sections of the
    /// currently active profile. An explicit profile can be passed right after
    /// a profile switch.
    private func loadFeatures(profile explicitProfile: Int? = nil) {
        guard let selected else { return }
        var failures: [String] = []

        if explicitProfile == nil || base == nil {
            do {
                base = try selected.connection.readBase()
            } catch {
                failures.append("配置档: \(error.localizedDescription)")
            }
        }
        let profile = explicitProfile ?? base?.profileIndex ?? 0

        do {
            keymap = try selected.connection.readKeymap(profile: profile)
        } catch {
            failures.append("键位: \(error.localizedDescription)")
        }
        do {
            triggers = try selected.connection.readTriggers(profile: profile)
        } catch {
            failures.append("磁轴: \(error.localizedDescription)")
        }
        do {
            light = try selected.connection.readLightConfig(profile: profile)
        } catch {
            failures.append("灯效: \(error.localizedDescription)")
        }

        if !failures.isEmpty {
            error = failures.joined(separator: "；")
        }

        logger.info(
            "features loaded profile=\(profile) keymap=\(self.keymap.count) triggers=\(self.triggers.count) light=\(self.light != nil) base=\(self.base != nil)"
        )
        for failure in failures {
            logger.error("feature load failure: \(failure, privacy: .public)")
        }
    }

    /// Runs a device operation on the main actor.
    ///
    /// When `snapshot` is true and writes are enabled, the current device state
    /// is saved before the body runs. A failed snapshot aborts the operation
    /// instead of writing without a safety net.
    private func perform(snapshot: Bool = true, _ body: () throws -> Void) {
        guard selected != nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if snapshot, writePolicy == .allow, let connection = selected?.connection {
                lastSnapshotURL = try SnapshotStore.save(try connection.captureSnapshot())
            }
            try body()
            error = nil
        } catch {
            status = "应用失败"
            self.error = error.localizedDescription
            logger.error("apply failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum SnapshotError: Error, LocalizedError {
    case noSnapshot

    var errorDescription: String? {
        switch self {
        case .noSnapshot:
            return "没有可用快照；先应用一次设置或运行 mchose-cli snapshot"
        }
    }
}
