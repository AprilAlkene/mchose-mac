import Features
import SwiftUI

/// Reads the 16 shared macro slots and keeps a minimal editor for them.
/// Full macro authoring (per-action delay, drag & drop, key assignment) is not
/// implemented; a slot can be cleared or filled from a compact text form.
struct MacroView: View {
    @ObservedObject var store: DeviceStore

    @State private var selectedIndex: Int = 0
    @State private var spec: String = "A:down A:up"

    var body: some View {
        PageScroll {
            if store.macroSlots.isEmpty {
                Card {
                    EmptyState(
                        icon: "list.bullet.rectangle",
                        title: "尚未读取宏",
                        message: store.selected == nil ? "连接设备后可用" : "正在读取设备…"
                    )
                }
            } else {
                Card("槽位") {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 4
                    ) {
                        ForEach(store.macroSlots) { slot in
                            slotRow(slot)
                        }
                    }

                    HStack {
                        Spacer()
                        Button("全部清空") { store.clearAllMacroSlots() }
                            .buttonStyle(.bordered)
                            .disabled(!store.canWrite || store.isBusy)
                    }
                    .padding(.top, 4)
                }

                Card("写入槽位") {
                    SettingRow("槽位") {
                        Picker("槽位", selection: $selectedIndex) {
                            ForEach(0..<MacroCodec.slotCount, id: \.self) { index in
                                Text("槽 \(index)").tag(index)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    SettingRow("动作") {
                        TextField("A:down A:up", text: $spec)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Spacer()
                        Button("写入该槽") {
                            let actions = parse(spec)
                            guard !actions.isEmpty else { return }
                            store.setMacroSlot(selectedIndex, actions: actions)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.canWrite || store.isBusy)
                    }
                }

                Text("文本格式：`键名:down` / `键名:up`，空格分隔（如 `Ctrl:down C:down C:up Ctrl:up`）。写入会整块下发宏区并回读校验，失败自动回滚。宏要生效还需在「改键」里把某个键设为宏类型，当前尚未实现。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func slotRow(_ slot: MacroSlot) -> some View {
        HStack(spacing: 6) {
            Text("槽 \(slot.index)")
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .leading)
            Text(slot.actions.isEmpty ? "空" : slot.actions.map(\.description).joined(separator: " · "))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(slot.actions.isEmpty ? Color(nsColor: .secondaryLabelColor) : Color.primary)
            Spacer(minLength: 2)
            Button("清空") { store.clearMacroSlot(slot.index) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!store.canWrite || store.isBusy)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(
            selectedIndex == slot.index ? Color.accentColor.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedIndex = slot.index }
        .help("槽 \(slot.index) · type \(slot.type)")
    }

    private func parse(_ text: String) -> [MacroAction] {
        var actions: [MacroAction] = []
        for token in text.split(separator: " ") {
            let parts = token.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let usage = KeyNameMap.hidUsage(forName: String(parts[0])),
                  parts[1] == "down" || parts[1] == "up" else {
                continue
            }
            actions.append(MacroAction(isDown: parts[1] == "down", code: usage))
        }
        return actions
    }
}
