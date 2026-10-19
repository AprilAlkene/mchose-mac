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

/// Device state read on the HID worker thread, applied to the UI on main.
private struct LoadedFeatures {
    var profile: Int = 0
    var base: BaseInfo?
    var keymap: [KeyInfo] = []
    var triggers: [TriggerConfig] = []
    var light: LightConfig?
    var failures: [String] = []
}

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [ConnectedDevice] = []
    @Published private(set) var selected: ConnectedDevice?
    @Published private(set) var info: DeviceInfo?
    @Published private(set) var triggers: [TriggerConfig] = []
    @Published private(set) var keymap: [KeyInfo] = []
    /// Keymap layers read on demand; layer 0 is filled at connect time.
    @Published private(set) var keymapLayers: [Int: [KeyInfo]] = [:]
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
    private let monitor = HIDDeviceMonitor()
    private var wakeObserver: NSObjectProtocol?
    /// Serializes all device I/O on a dedicated run-loop thread. IOKit
    /// delivers input reports on the run loop where the device was scheduled,
    /// so every connection operation has to stay on this one thread.
    private let ioWorker = HIDRunLoopWorker()
    /// Debounces hotplug events and drops the launch-time enumeration.
    private var hotplugGeneration = 0

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
        monitor.onDevicesChanged = { [weak self] _ in
            Task { @MainActor in self?.handleHotplug() }
        }
        monitor.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
        logger.info(
            "manifest loaded: \(self.manifest?.displayName ?? "none", privacy: .public) policy=\(String(describing: self.writePolicy), privacy: .public)"
        )
        // Start enumerating right away instead of waiting for the first view
        // task, which can take seconds during app launch.
        refresh(force: false)
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

    // MARK: - Device discovery

    private func handleHotplug() {
        hotplugGeneration += 1
        waitForHotplugStability(generation: hotplugGeneration, attempt: 0)
    }

    /// A background operation can still be running when the device changes;
    /// retry until it settles, but give up quickly instead of polling forever.
    private func waitForHotplugStability(generation: Int, attempt: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.hotplugGeneration == generation else { return }
            if self.isBusy {
                if attempt < 8 {
                    self.waitForHotplugStability(generation: generation, attempt: attempt + 1)
                }
                return
            }
            self.refresh(force: false)
        }
    }

    /// Re-enumerates devices and reconnects only when the matched set changed.
    func refresh() {
        refresh(force: false)
    }

    private func refresh(force: Bool) {
        guard !isBusy else { return }
        guard let manifest else {
            status = "设备清单加载失败"
            return
        }
        let previousID = selected?.id
        let enumerator = self.enumerator
        let started = DispatchTime.now()
        logger.info("refresh start force=\(force)")
        isBusy = true
        ioWorker.perform { [weak self] in
            let scanned = Self.scanDevices(enumerator: enumerator, manifest: manifest)
            Task { @MainActor [weak self] in
                self?.finishScan(
                    scanned,
                    previousID: previousID,
                    force: force,
                    started: started
                )
            }
        }
    }

    private nonisolated static func scanDevices(
        enumerator: HIDEnumerator,
        manifest: DeviceManifest
    ) -> [ConnectedDevice] {
        enumerator.listDevices()
            .filter {
                DeviceMatcher.matches(info: $0.info, manifest: manifest)
                    && $0.info.interface.isConfigurationInterface
            }
            .map { ConnectedDevice(ref: $0, manifest: manifest) }
    }

    private func finishScan(
        _ scanned: [ConnectedDevice],
        previousID: String?,
        force: Bool,
        started: DispatchTime
    ) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        logger.info("scan finished in \(elapsed, format: .fixed(precision: 0)) ms")
        if !force, selected != nil, Set(scanned.map(\.id)) == Set(devices.map(\.id)) {
            isBusy = false
            return
        }
        let oldConnection = selected?.connection
        ioWorker.perform { [weak self] in
            oldConnection?.close()
            Task { @MainActor [weak self] in
                self?.applyScan(scanned, previousID: previousID)
            }
        }
    }

    private func applyScan(_ scanned: [ConnectedDevice], previousID: String?) {
        devices = scanned
        logger.info("scan complete: \(scanned.count) device(s)")

        if let previousID, let match = scanned.first(where: { $0.id == previousID }) {
            selected = match
        } else {
            selected = scanned.first
            info = nil
            triggers = []
            keymap = []
            keymapLayers = [:]
            light = nil
            base = nil
        }
        applyWritePolicy()
        isBusy = false

        guard !scanned.isEmpty else {
            status = previousID == nil ? "未连接" : "设备已断开"
            return
        }
        status = "已发现 \(scanned.count) 个设备"
        connectSelected()
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
        keymapLayers = [:]
        light = nil
        base = nil
    }

    // MARK: - Connecting

    func connectSelected() {
        guard !isBusy, let selected else { return }
        let connection = selected.connection
        connection.writePolicy = writePolicy
        isBusy = true
        ioWorker.perform { [weak self] in
            var info: DeviceInfo?
            var features: LoadedFeatures?
            var failure: Error?
            do {
                try connection.connect()
                info = try connection.readInfo()
                features = Self.readFeatures(connection, profile: nil, includeBase: true)
            } catch {
                failure = error
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBusy = false
                if let failure {
                    self.status = "连接失败"
                    self.error = failure.localizedDescription
                    self.info = nil
                    logger.error("connect failed: \(failure.localizedDescription, privacy: .public)")
                    return
                }
                self.info = info
                self.error = nil
                if let features {
                    self.applyFeatures(features)
                }
                self.status = "已连接"
                if let info {
                    logger.info(
                        "connected \(info.product, privacy: .public) firmware \(info.firmwareVersion ?? "unknown", privacy: .public) build \(info.buildDate, privacy: .public)"
                    )
                }
            }
        }
    }

    func disconnectSelected() {
        guard let connection = selected?.connection else { return }
        ioWorker.perform { [weak self] in
            connection.close()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.info = nil
                self.triggers = []
                self.keymap = []
                self.keymapLayers = [:]
                self.light = nil
                self.base = nil
                self.status = "未连接"
            }
        }
    }

    // MARK: - Applying changes

    func applyTriggers(_ updated: [TriggerConfig]) {
        let profile = base?.profileIndex ?? 0
        applyFeature(
            "磁轴",
            operation: { try $0.applyTriggers(updated, profile: profile) },
            readback: { try $0.readTriggers(profile: profile) },
            update: { [weak self] in self?.triggers = $0 }
        )
    }

    func applyKeymap(_ updated: [KeyInfo], layer: Int = 0) {
        let profile = base?.profileIndex ?? 0
        applyFeature(
            layer == 0 ? "键位" : "键位（第 \(layer + 1) 层）",
            operation: { try $0.applyKeymap(updated, layer: layer, profile: profile) },
            readback: { try $0.readKeymap(layer: layer, profile: profile) },
            update: { [weak self] in
                self?.keymapLayers[layer] = $0
                if layer == 0 {
                    self?.keymap = $0
                }
            }
        )
    }

    /// Reads a keymap layer on demand; the UI calls this when the user selects
    /// a layer other than the one loaded at connect time.
    func loadLayer(_ layer: Int) {
        guard keymapLayers[layer] == nil,
              !isBusy,
              let connection = selected?.connection
        else {
            return
        }
        let profile = base?.profileIndex ?? 0
        isBusy = true
        ioWorker.perform { [weak self] in
            var keys: [KeyInfo]?
            var failure: Error?
            do {
                keys = try connection.readKeymap(layer: layer, profile: profile)
            } catch {
                failure = error
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBusy = false
                if let failure {
                    self.error = failure.localizedDescription
                    self.status = "读取图层失败"
                    return
                }
                if let keys {
                    self.keymapLayers[layer] = keys
                }
            }
        }
    }

    func applyLight(_ updated: LightConfig) {
        let profile = base?.profileIndex ?? 0
        applyFeature(
            "灯效",
            operation: { try $0.applyLightConfig(updated, profile: profile) },
            readback: { try $0.readLightConfig(profile: profile) },
            update: { [weak self] in self?.light = $0 }
        )
    }

    /// Writes one feature, captures a snapshot first (when writes are enabled)
    /// and reads the value back on the worker thread.
    private func applyFeature<T>(
        _ feature: String,
        operation: @escaping (DeviceConnection) throws -> Void,
        readback: @escaping (DeviceConnection) throws -> T,
        update: @escaping (T) -> Void
    ) {
        guard !isBusy, let connection = selected?.connection else { return }
        let policy = writePolicy
        isBusy = true
        ioWorker.perform { [weak self] in
            var failure: Error?
            var value: T?
            var savedSnapshot: URL?
            do {
                if policy == .allow {
                    savedSnapshot = try SnapshotStore.save(try connection.captureSnapshot())
                }
                try operation(connection)
                value = try readback(connection)
            } catch {
                failure = error
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let savedSnapshot {
                    self.lastSnapshotURL = savedSnapshot
                }
                self.isBusy = false
                if let failure {
                    self.status = "应用失败"
                    self.error = failure.localizedDescription
                    logger.error("apply failed: \(failure.localizedDescription, privacy: .public)")
                } else if let value {
                    update(value)
                    self.error = nil
                    self.status = self.applyStatus(feature)
                }
            }
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
        guard !isBusy, let connection = selected?.connection else { return }
        let policy = writePolicy
        isBusy = true
        ioWorker.perform { [weak self] in
            var failure: Error?
            var baseInfo: BaseInfo?
            var features: LoadedFeatures?
            do {
                try connection.switchProfile(index)
                baseInfo = try connection.readBase()
                features = Self.readFeatures(connection, profile: index, includeBase: false)
            } catch {
                failure = error
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBusy = false
                if let failure {
                    self.status = "应用失败"
                    self.error = failure.localizedDescription
                    logger.error("switch profile failed: \(failure.localizedDescription, privacy: .public)")
                    return
                }
                self.base = baseInfo
                self.error = nil
                if let features {
                    self.applyFeatures(features)
                }
                self.status = policy == .dryRun
                    ? "配置档切换已编码（dry-run，未写入）"
                    : "已切换到配置档 \(index + 1)"
            }
        }
    }

    func restoreLastSnapshot() {
        guard let connection = selected?.connection else { return }
        guard canWrite else {
            error = "只读模式，未恢复快照"
            return
        }
        guard !isBusy else { return }
        let policy = writePolicy
        let lastURL = lastSnapshotURL
        isBusy = true
        ioWorker.perform { [weak self] in
            var failure: Error?
            var restoredURL: URL?
            var info: DeviceInfo?
            var features: LoadedFeatures?
            do {
                let url = try Self.resolveSnapshotURL(last: lastURL)
                let snapshot = try SnapshotStore.load(from: url)
                try connection.restore(snapshot)
                info = try connection.readInfo()
                features = Self.readFeatures(connection, profile: nil, includeBase: true)
                restoredURL = url
            } catch {
                failure = error
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBusy = false
                if let failure {
                    self.status = "恢复失败"
                    self.error = failure.localizedDescription
                    logger.error("restore failed: \(failure.localizedDescription, privacy: .public)")
                    return
                }
                self.info = info
                self.error = nil
                if let features {
                    self.applyFeatures(features)
                }
                self.lastSnapshotURL = restoredURL
                self.status = policy == .dryRun
                    ? "dry-run：快照已校验，未写入"
                    : "已恢复快照 \(restoredURL?.lastPathComponent ?? "")"
            }
        }
    }

    private nonisolated static func resolveSnapshotURL(last: URL?) throws -> URL {
        if let last {
            return last
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

    // MARK: - Reading

    /// Reads base (optional) and the keymap/trigger/lighting sections of one
    /// profile. Runs on the worker thread; no UI state is touched here.
    private nonisolated static func readFeatures(
        _ connection: DeviceConnection,
        profile explicitProfile: Int?,
        includeBase: Bool
    ) -> LoadedFeatures {
        var loaded = LoadedFeatures()
        var failures: [String] = []

        if includeBase {
            do {
                loaded.base = try connection.readBase()
            } catch {
                failures.append("配置档: \(error.localizedDescription)")
            }
        }
        let profile = explicitProfile ?? loaded.base?.profileIndex ?? 0
        loaded.profile = profile

        do {
            loaded.keymap = try connection.readKeymap(profile: profile)
        } catch {
            failures.append("键位: \(error.localizedDescription)")
        }
        do {
            loaded.triggers = try connection.readTriggers(profile: profile)
        } catch {
            failures.append("磁轴: \(error.localizedDescription)")
        }
        do {
            loaded.light = try connection.readLightConfig(profile: profile)
        } catch {
            failures.append("灯效: \(error.localizedDescription)")
        }

        loaded.failures = failures
        logger.info(
            "features read on \(Thread.isMainThread ? "main" : "worker", privacy: .public) thread=\(Thread.current.name ?? "unnamed", privacy: .public)"
        )
        return loaded
    }

    private func applyFeatures(_ loaded: LoadedFeatures) {
        if let base = loaded.base {
            self.base = base
        }
        keymap = loaded.keymap
        keymapLayers = [0: loaded.keymap]
        triggers = loaded.triggers
        light = loaded.light

        if !loaded.failures.isEmpty {
            error = loaded.failures.joined(separator: "；")
        }
        logger.info(
            "features loaded profile=\(loaded.profile) keymap=\(loaded.keymap.count) triggers=\(loaded.triggers.count) light=\(loaded.light != nil) base=\(loaded.base != nil)"
        )
        for failure in loaded.failures {
            logger.error("feature load failure: \(failure, privacy: .public)")
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
