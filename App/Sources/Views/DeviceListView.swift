import SwiftUI

struct DeviceListView: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        List(store.devices) { device in
            HStack {
                Text(device.ref.info.product)
                Spacer()
                Text(
                    String(
                        format: "0x%04X:0x%04X",
                        device.ref.info.identity.vendorId,
                        device.ref.info.identity.productId
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { store.select(device) }
            .background(
                store.selected?.id == device.id
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
        }
        .frame(height: 120)
    }
}
