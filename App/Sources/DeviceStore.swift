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
    @Published private(set) var status: String = "未连接"
    @Published private(set) var error: String?

    private let manifest: DeviceManifest?
    private let enumerator = HIDEnumerator()

    init() {
        manifest = try? ManifestLoader.loadBundled()
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
    }

    func connectSelected() {
        guard let selected else { return }
        do {
            try selected.connection.connect()
            info = try selected.connection.readInfo()
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
        status = "未连接"
    }
}
