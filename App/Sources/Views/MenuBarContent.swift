import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject var switcher = ProfileSwitcher.shared

    var body: some View {
        Text(store.status)

        if let base = store.base {
            Menu("配置档 \(base.profileIndex + 1) / \(base.profileCount)") {
                ForEach(0..<base.profileCount, id: \.self) { index in
                    Button("配置档 \(index + 1)") {
                        store.switchProfile(index)
                    }
                }
            }
        }

        Toggle("随应用切换", isOn: $switcher.isEnabled)

        Divider()

        Button("扫描设备") { store.refresh() }
        Button("连接") { store.connectSelected() }
        Button("断开") { store.disconnectSelected() }

        Divider()

        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}
