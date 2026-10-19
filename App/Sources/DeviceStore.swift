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

    let switcher = ProfileSwitcher.shared

    private let manifest: DeviceManifest?
    private let enumerator = HIDEnumerator()

    init() {
        manifest = try? ManifestLoader.loadBundled()
        switcher.onSwitch = { [weak self] index in
            self?.switchProfile(index)
        }
        switcher.start()
        logger.info("manifest loaded: \(self.manifest?.displayName ?? "none", privacy: .public)")
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

    func select(_ device: ConnectedDevice) {
        selected = device
        info = nil
        triggers = []
        keymap = []
        light = nil
        base = nil
    }

    func connectSelected() {
        guard let selected else { return }
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

    func applyTriggers(_ updated: [TriggerConfig]) {
        perform {
            try self.selected?.connection.writeTriggers(updated)
            self.triggers = try self.selected?.connection.readTriggers() ?? []
            self.status = "磁轴已应用"
        }
    }

    func applyKeymap(_ updated: [KeyInfo]) {
        perform {
            try self.selected?.connection.writeKeymap(updated)
            self.keymap = try self.selected?.connection.readKeymap() ?? []
            self.status = "键位已应用"
        }
    }

    func applyLight(_ updated: LightConfig) {
        perform {
            try self.selected?.connection.writeLightConfig(updated)
            self.light = try self.selected?.connection.readLightConfig()
            self.status = "灯效已应用"
        }
    }

    func switchProfile(_ index: Int) {
        perform {
            try self.selected?.connection.switchProfile(index)
            self.base = try self.selected?.connection.readBase()
            self.loadFeatures()
            self.status = "已切换到配置档 \(index + 1)"
        }
    }

    private func loadFeatures() {
        guard let selected else { return }
        var failures: [String] = []

        do {
            keymap = try selected.connection.readKeymap()
        } catch {
            failures.append("键位: \(error.localizedDescription)")
        }
        do {
            triggers = try selected.connection.readTriggers()
        } catch {
            failures.append("磁轴: \(error.localizedDescription)")
        }
        do {
            light = try selected.connection.readLightConfig()
        } catch {
            failures.append("灯效: \(error.localizedDescription)")
        }
        do {
            base = try selected.connection.readBase()
        } catch {
            failures.append("配置档: \(error.localizedDescription)")
        }

        if !failures.isEmpty {
            error = failures.joined(separator: "；")
        }

        logger.info(
            "features loaded keymap=\(self.keymap.count) triggers=\(self.triggers.count) light=\(self.light != nil) base=\(self.base != nil)"
        )
        for failure in failures {
            logger.error("feature load failure: \(failure, privacy: .public)")
        }
    }

    private func perform(_ body: () throws -> Void) {
        guard selected != nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try body()
            error = nil
        } catch {
            status = "应用失败"
            self.error = error.localizedDescription
            logger.error("apply failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
