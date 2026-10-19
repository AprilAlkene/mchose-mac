import SwiftUI
import Features

/// Read/show the 16 shared macro slots and keep a minimal editor for them.
/// Full macro authoring (per-action delay, drag & drop, key assignment) is not
/// implemented; a slot can be cleared or filled from a compact text form.
struct MacroView: View {
    @ObservedObject var store: DeviceStore

    @State private var selectedIndex: Int = 0
    @State private var spec: String = "A:down A:up"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("宏")
                    .font(.headline)
                Text("16 个共享槽位，所有配置档共用")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全部清空") { store.clearAllMacroSlots() }
                .disabled(store.macroSlots.isEmpty || !store.canWrite || store.isBusy)
            }

            if store.macroSlots.isEmpty {
                Text(store.selected == nil ? "连接设备后可用" : "正在读取…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(store.macroSlots) { slot in
                    HStack(alignment: .firstTextBaseline) {
                        Text("槽 \(slot.index)")
                            .monospaced()
                            .frame(width: 46, alignment: .leading)
                        Text("type \(slot.type)")
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        Text(
                            slot.actions.isEmpty
                                ? "空"
                                : slot.actions.map(\.description).joined(separator: ", ")
                        )
                        .lineLimit(2)
                        .font(.footnote)
                        Spacer()
                        Button("清空") { store.clearMacroSlot(slot.index) }
                            .disabled(!store.canWrite || store.isBusy)
                    }
                }
                .frame(minHeight: 220)
            }

            Divider()

            HStack {
                Picker("槽位", selection: $selectedIndex) {
                    ForEach(0..<MacroCodec.slotCount, id: \.self) { index in
                        Text("槽 \(index)").tag(index)
                    }
                }
                .frame(width: 160)
                TextField("A:down A:up", text: $spec)
                    .textFieldStyle(.roundedBorder)
                Button("写入该槽") {
                    let actions = parse(spec)
                    guard !actions.isEmpty else { return }
                    store.setMacroSlot(selectedIndex, actions: actions)
                }
                .disabled(!store.canWrite || store.isBusy)
            }

            Text("文本格式：`键名:down` / `键名:up`，空格分隔（如 `Ctrl:down C:down C:up Ctrl:up`）。写入会整块下发宏区并回读校验，失败自动回滚。宏要生效还需在「改键」里把某个键设为宏类型，当前尚未实现。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
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
