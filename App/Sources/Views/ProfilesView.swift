import SwiftUI

struct ProfilesView: View {
    @ObservedObject var store: DeviceStore
    @ObservedObject var switcher = ProfileSwitcher.shared

    @State private var targetProfile = 0

    private var profileBinding: Binding<Int> {
        Binding(
            get: { store.base?.profileIndex ?? 0 },
            set: { store.switchProfile($0) }
        )
    }

    var body: some View {
        PageScroll {
            Card("当前配置档") {
                if let base = store.base {
                    SettingRow("活动档") {
                        Text("配置档 \(base.profileIndex + 1) / \(base.profileCount)")
                            .font(.callout.weight(.medium))
                    }
                    Picker("配置档", selection: profileBinding) {
                        ForEach(0..<base.profileCount, id: \.self) { index in
                            Text("配置档 \(index + 1)").tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(store.isBusy || !store.canWrite)
                } else {
                    EmptyState(
                        icon: "square.stack.3d.up",
                        title: "尚未加载配置档",
                        message: store.selected == nil ? "连接设备后可用" : "正在读取设备…"
                    )
                }
            }

            Card("随前台应用切换") {
                Toggle("启用自动切换", isOn: $switcher.isEnabled)
                    .disabled(!store.canWrite)

                SettingRow("当前应用") {
                    Text(switcher.frontmostName ?? "—")
                        .foregroundStyle(.secondary)
                }

                SettingRow("绑定到") {
                    HStack(spacing: 10) {
                        Picker("绑定到配置档", selection: $targetProfile) {
                            ForEach(0..<(store.base?.profileCount ?? 4), id: \.self) { index in
                                Text("配置档 \(index + 1)").tag(index)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)

                        Button("绑定当前应用") {
                            switcher.bindCurrentApp(to: targetProfile)
                        }
                        .buttonStyle(.bordered)
                        .disabled(switcher.frontmostBundleID == nil)
                    }
                }
            }

            if !switcher.mappings.isEmpty {
                Card("已绑定应用") {
                    VStack(spacing: 2) {
                        ForEach(Array(switcher.mappings.keys.sorted()), id: \.self) { bundleID in
                            HStack(spacing: 10) {
                                Text(bundleID)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("配置档 \((switcher.mappings[bundleID] ?? 0) + 1)")
                                    .font(.callout)
                                Button("删除") { switcher.remove(bundleID) }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
    }
}
