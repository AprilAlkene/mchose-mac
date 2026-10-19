import AppKit
import Features
import SwiftUI

/// Edits the per-key RGB block of the active profile. The firmware shows these
/// colors with the still/per-key effect (effect id 65, "逐键静态").
struct PerKeyLightView: View {
    @ObservedObject var store: DeviceStore

    @State private var selectedIndex: Int = 0
    @State private var color: Color = .red

    private var colors: [KeyColor] { store.keyColors }

    private var selectedEntry: KeyColor {
        guard selectedIndex < colors.count else { return .off }
        return colors[selectedIndex]
    }

    var body: some View {
        PageScroll {
            if colors.isEmpty {
                Card {
                    EmptyState(
                        icon: "square.grid.3x3",
                        title: "尚未读取逐键颜色",
                        message: store.selected == nil ? "连接设备后可用" : "正在读取设备…"
                    )
                }
            } else {
                HStack(spacing: 10) {
                    Text("\(colors.count) 键 · 主灯效设为 65 后生效")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("全部熄灭") {
                        store.applyKeyColors(Array(repeating: .off, count: colors.count))
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canWrite || store.isBusy)
                    Button("应用逐键颜色") { store.applyKeyColors(colors) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.canWrite || store.isBusy)
                }

                Card("颜色矩阵") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 16),
                        spacing: 4
                    ) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { index, entry in
                            Button {
                                selectedIndex = index
                                color = swatch(entry)
                            } label: {
                                Text(label(index))
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.55)
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .background(swatch(entry))
                                    .foregroundStyle(luminance(entry) > 0.55 ? .black : .white)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(
                                                selectedIndex == index
                                                    ? Color.accentColor
                                                    : Color.primary.opacity(0.08),
                                                lineWidth: selectedIndex == index ? 2 : 0.5
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .help("键 \(index) \(name(index))：\(entry.hex)")
                        }
                    }
                }

                Card("选中键") {
                    SettingRow("按键") {
                        Text("index \(selectedIndex) · \(name(selectedIndex))")
                            .font(.callout.weight(.medium))
                    }
                    SettingRow("颜色") {
                        HStack(spacing: 10) {
                            ColorPicker("颜色", selection: $color, supportsOpacity: false)
                                .labelsHidden()
                            Text(selectedEntry.hex)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("设为当前颜色") {
                            guard selectedIndex < colors.count else { return }
                            var updated = colors
                            updated[selectedIndex] = rgb(color)
                            store.applyKeyColors(updated)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.canWrite || store.isBusy)
                    }
                }

                Text("index 0–127 为固件矩阵顺序；写前会自动快照，写入后回读校验，失败会自动回滚。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { color = swatch(selectedEntry) }
        .onChange(of: store.keyColors) { _ in color = swatch(selectedEntry) }
    }

    private func name(_ index: Int) -> String {
        index < store.keymap.count ? store.keymap[index].name : "\(index)"
    }

    /// Compact key cap label: symbolic for the common keys, a dot for the
    /// unnamed firmware entries, the plain name otherwise.
    private func label(_ index: Int) -> String {
        guard index < store.keymap.count else { return "\(index)" }
        let name = store.keymap[index].name
        if name.hasPrefix("Type ") || name.hasPrefix("0x") { return "·" }
        switch name {
        case "Backspace": return "⌫"
        case "Enter": return "⏎"
        case "Space": return "␣"
        case "CapsLock": return "⇪"
        case "Tab": return "⇥"
        case "Delete": return "⌦"
        case "Left": return "←"
        case "Right": return "→"
        case "Up": return "↑"
        case "Down": return "↓"
        case "PageUp": return "⇞"
        case "PageDown": return "⇟"
        case "Insert": return "Ins"
        default: return name
        }
    }

    private func swatch(_ entry: KeyColor) -> Color {
        Color(
            red: Double(entry.red) / 255,
            green: Double(entry.green) / 255,
            blue: Double(entry.blue) / 255
        )
    }

    private func luminance(_ entry: KeyColor) -> Double {
        0.299 * Double(entry.red) / 255 +
            0.587 * Double(entry.green) / 255 +
            0.114 * Double(entry.blue) / 255
    }

    private func rgb(_ color: Color) -> KeyColor {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else {
            return .off
        }
        return KeyColor(
            red: UInt8((converted.redComponent * 255).rounded()),
            green: UInt8((converted.greenComponent * 255).rounded()),
            blue: UInt8((converted.blueComponent * 255).rounded())
        )
    }
}
