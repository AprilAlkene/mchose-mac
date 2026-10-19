import SwiftUI
import AppKit
import Features

/// Edits the per-key RGB block of the active profile. The firmware shows these
/// colors with the still/per-key effect (effect id 65, "逐键静态").
struct PerKeyLightView: View {
    @ObservedObject var store: DeviceStore

    @State private var selectedIndex: Int = 0
    @State private var color: Color = .red
    @State private var lastSelectedIndex: Int = 0

    private var colors: [KeyColor] { store.keyColors }

    private var currentColor: KeyColor {
        guard selectedIndex < colors.count else { return .off }
        return colors[selectedIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("逐键灯效")
                    .font(.headline)
                Text("\(colors.count) 键")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("应用逐键颜色") { apply() }
                    .disabled(colors.isEmpty || !store.canWrite || store.isBusy)
                Button("全部熄灭") {
                    store.applyKeyColors(Array(repeating: .off, count: colors.count))
                }
                .disabled(colors.isEmpty || !store.canWrite || store.isBusy)
            }

            Text("先在「灯效」页把主灯效设为 65（逐键静态），逐键颜色才会显示。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if colors.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("未读取逐键灯效")
                    Text(store.selected == nil ? "连接设备后可用" : "正在读取…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(44), spacing: 4), count: 16),
                        spacing: 4
                    ) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { index, entry in
                            let name = index < store.keymap.count ? store.keymap[index].name : "\(index)"
                            Button {
                                selectedIndex = index
                                color = Color(
                                    red: Double(entry.red) / 255,
                                    green: Double(entry.green) / 255,
                                    blue: Double(entry.blue) / 255
                                )
                            } label: {
                                Text(name)
                                    .font(.system(size: 8))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(width: 44, height: 26)
                                    .background(swatch(entry))
                                    .foregroundStyle(luminance(entry) > 0.55 ? .black : .white)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(selectedIndex == index ? Color.accentColor : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("键 \(index) \(name): \(entry.hex)")
                        }
                    }
                    .padding(2)
                }
            }

            Divider()

            HStack {
                Text("选中键 \(selectedIndex)")
                if selectedIndex < store.keymap.count {
                    Text(store.keymap[selectedIndex].name)
                        .foregroundStyle(.secondary)
                }
                ColorPicker("颜色", selection: $color, supportsOpacity: false)
                Text(hex(selectedIndex))
                    .monospaced()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("设为当前颜色") {
                    guard selectedIndex < colors.count else { return }
                    var updated = colors
                    updated[selectedIndex] = rgb(color)
                    store.applyKeyColors(updated)
                }
                .disabled(colors.isEmpty || !store.canWrite || store.isBusy)
            }

            Text("index 0–127 为固件矩阵顺序；写前会自动快照，写入后回读校验，失败会自动回滚。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onChange(of: selectedIndex) { _ in
            lastSelectedIndex = selectedIndex
        }
    }

    private func apply() {
        store.applyKeyColors(colors)
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

    private func hex(_ index: Int) -> String {
        guard index < colors.count else { return "—" }
        return colors[index].hex
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
