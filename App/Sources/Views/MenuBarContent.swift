import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        Text(store.status)
        Button("扫描设备") { store.refresh() }
        Button("连接") { store.connectSelected() }
        Button("断开") { store.disconnectSelected() }
        Divider()
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}
