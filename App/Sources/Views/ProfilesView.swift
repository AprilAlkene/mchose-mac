import SwiftUI

struct ProfilesView: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject var switcher = ProfileSwitcher.shared

    @State private var targetProfile = 0

    var body: some View {
        Form {
            if let base = store.base {
                LabeledContent("当前配置档") {
                    Text("\(base.profileIndex + 1) / \(base.profileCount)")
                }

                HStack {
                    ForEach(0..<base.profileCount, id: \.self) { index in
                        Button("\(index + 1)") {
                            store.switchProfile(index)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(index == base.profileIndex ? .accentColor : .gray)
                    }
                }
                .disabled(store.isBusy || !store.canWrite)
            } else {
                Text("连接设备后加载配置档")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("随前台应用自动切换", isOn: $switcher.isEnabled)
                .disabled(!store.canWrite)

            LabeledContent("当前前台应用") {
                Text(switcher.frontmostName ?? "-")
            }

            Picker("绑定到配置档", selection: $targetProfile) {
                ForEach(0..<(store.base?.profileCount ?? 4), id: \.self) { index in
                    Text("配置档 \(index + 1)").tag(index)
                }
            }

            Button("绑定当前应用") {
                switcher.bindCurrentApp(to: targetProfile)
            }
            .disabled(switcher.frontmostBundleID == nil)

            if !switcher.mappings.isEmpty {
                Text("已绑定应用")
                    .font(.headline)

                ForEach(Array(switcher.mappings.keys.sorted()), id: \.self) { bundleID in
                    let profile = switcher.mappings[bundleID] ?? 0
                    HStack {
                        Text(bundleID)
                            .font(.caption)
                        Spacer()
                        Text("配置档 \(profile + 1)")
                        Button("删除") {
                            switcher.remove(bundleID)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
