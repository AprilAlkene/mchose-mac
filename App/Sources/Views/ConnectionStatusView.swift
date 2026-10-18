import SwiftUI

struct ConnectionStatusView: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.status)
                .font(.subheadline.weight(.medium))
            if let error = store.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
