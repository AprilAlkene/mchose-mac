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
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!store.canWrite)

                Text("切到下面绑定的应用时自动切换配置档；本 App 激活时不触发。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                SettingRow("目标配置档") {
                    Picker("目标配置档", selection: $targetProfile) {
                        ForEach(0..<(store.base?.profileCount ?? 4), id: \.self) { index in
                            Text("配置档 \(index + 1)").tag(index)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                SettingRow("绑定应用") {
                    Menu {
                        if switcher.bindableApps.isEmpty {
                            Text("没有正在运行的普通应用")
                        } else {
                            ForEach(switcher.bindableApps) { app in
                                Button(app.name) {
                                    switcher.bind(app, to: targetProfile)
                                }
                            }
                        }
                    } label: {
                        Label("选择应用…", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(switcher.bindableApps.isEmpty)
                }

                Text("仅列出正在运行的普通应用（不含本 App）。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            .onChange(of: store.base) { base in
                let count = base?.profileCount ?? 1
                targetProfile = min(targetProfile, max(count - 1, 0))
            }

            if !switcher.mappings.isEmpty {
                Card("已绑定应用") {
                    VStack(spacing: 2) {
                        ForEach(Array(switcher.mappings.keys.sorted()), id: \.self) { bundleID in
                            HStack(spacing: 10) {
                                Text(switcher.name(for: bundleID))
                                    .font(.callout)
                                    .lineLimit(1)
                                    .help(bundleID)
                                Spacer()
                                Text("配置档 \((switcher.mappings[bundleID] ?? 0) + 1)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
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
