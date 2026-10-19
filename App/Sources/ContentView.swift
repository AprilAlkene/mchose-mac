import SwiftUI
import Features

struct ContentView: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MCHOSE Mac")
                    .font(.largeTitle.bold())
                Spacer()
                if store.writePolicy != .allow {
                    Text(store.policyLabel)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18))
                        .clipShape(Capsule())
                }
                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ConnectionStatusView(store: store)
            DeviceListView(store: store)

            HStack {
                Button("扫描设备") { store.refresh() }
                Button("连接") { store.connectSelected() }
                    .disabled(store.selected == nil)
                Button("断开") { store.disconnectSelected() }
                    .disabled(store.selected == nil)

                Divider()
                    .frame(height: 18)

                Button("恢复上次快照") { store.restoreLastSnapshot() }
                    .disabled(store.selected == nil || !store.canWrite)
                    .help("把设备恢复到最近一次应用设置之前的状态")
            }

            Divider()

            TabView {
                MagneticView(store: store)
                    .tabItem { Label("磁轴", systemImage: "slider.horizontal.3") }

                KeymapView(store: store)
                    .tabItem { Label("改键", systemImage: "keyboard") }

                LightingView(store: store)
                    .tabItem { Label("灯效", systemImage: "lightbulb") }

                ProfilesView(store: store)
                    .tabItem { Label("配置档", systemImage: "square.stack.3d.up") }

                DeviceInfoView(info: store.info)
                    .tabItem { Label("信息", systemImage: "info.circle") }
            }
            .frame(minHeight: 300)
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
        .task { store.refresh() }
    }
}
