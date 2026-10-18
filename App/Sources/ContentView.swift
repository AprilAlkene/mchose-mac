import SwiftUI

struct ContentView: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MCHOSE Mac")
                .font(.largeTitle.bold())

            ConnectionStatusView(store: store)
            DeviceListView(store: store)
            Divider()
            DeviceInfoView(info: store.info)

            Spacer()

            HStack {
                Button("扫描设备") { store.refresh() }
                Button("连接") { store.connectSelected() }
                    .disabled(store.selected == nil)
                Button("断开") { store.disconnectSelected() }
                    .disabled(store.selected == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 380)
        .task { store.refresh() }
    }
}
