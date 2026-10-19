import Features
import SwiftUI

struct LightingView: View {
    @ObservedObject var store: DeviceStore

    @State private var draft: LightConfig?
    @State private var mainColor: Color = .red
    @State private var sideColor: Color = .red

    var body: some View {
        PageScroll {
            if let light = draft {
                Card("主灯") {
                    SettingRow("模式") {
                        Stepper(
                            value: Binding(
                                get: { Int(light.effect) },
                                set: { newValue in
                                    update { $0.effect = UInt8(clamping: newValue) }
                                }
                            ),
                            in: 0...65
                        ) {
                            Text("灯效 ID \(light.effect)")
                                .monospacedDigit()
                        }
                    }

                    Text("0–22 为动态灯效；65 为逐键静态，颜色在「逐键灯效」页设置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    SettingRow("亮度") {
                        percentSlider(value: light.brightness) { newValue in
                            update { $0.brightness = newValue }
                        }
                    }
                    SettingRow("速度") {
                        speedSlider(value: light.speed) { newValue in
                            update { $0.speed = newValue }
                        }
                    }
                    SettingRow("颜色") {
                        HStack(spacing: 10) {
                            ColorPicker("主颜色", selection: $mainColor, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: mainColor) { _ in updateMainColor() }
                            Text(light.hexColor)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    SettingRow("随机色") {
                        Toggle(
                            "主灯随机色",
                            isOn: Binding(
                                get: { light.customColorDisabled == 1 },
                                set: { isRandom in
                                    update { $0.customColorDisabled = isRandom ? 1 : 0 }
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                Card("侧灯") {
                    SettingRow("亮度") {
                        percentSlider(value: light.sideBrightness) { newValue in
                            update { $0.sideBrightness = newValue }
                        }
                    }
                    SettingRow("速度") {
                        speedSlider(value: light.sideSpeed) { newValue in
                            update { $0.sideSpeed = newValue }
                        }
                    }
                    SettingRow("颜色") {
                        HStack(spacing: 10) {
                            ColorPicker("侧灯颜色", selection: $sideColor, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: sideColor) { _ in updateSideColor() }
                            Text(light.sideHexColor)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    SettingRow("随机色") {
                        Toggle(
                            "侧灯随机色",
                            isOn: Binding(
                                get: { light.sideCustomColorDisabled == 1 },
                                set: { isRandom in
                                    update { $0.sideCustomColorDisabled = isRandom ? 1 : 0 }
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                HStack {
                    Spacer()
                    Button("应用灯效") { apply() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isBusy || !store.canWrite)
                }
            } else {
                Card {
                    EmptyState(
                        icon: "lightbulb",
                        title: "尚未加载灯效",
                        message: store.selected == nil ? "连接设备后可用" : "正在读取设备…"
                    )
                }
            }
        }
        .onAppear { sync() }
        .onChange(of: store.light) { _ in sync() }
    }

    private func percentSlider(
        value: UInt8,
        set: @escaping (UInt8) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { set(UInt8(clamping: Int($0))) }
                ),
                in: 0...100,
                step: 1
            )
            Text("\(value)%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func speedSlider(
        value: UInt8,
        set: @escaping (UInt8) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { set(UInt8(clamping: Int($0))) }
                ),
                in: 0...4,
                step: 1
            )
            Text("\(value) / 4")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func sync() {
        guard let light = store.light else {
            draft = nil
            return
        }
        draft = light
        mainColor = Color(hex: light.hexColor)
        sideColor = Color(hex: light.sideHexColor)
    }

    private func update(_ body: (inout LightConfig) -> Void) {
        guard var value = draft else { return }
        body(&value)
        draft = value
    }

    private func updateMainColor() {
        // The vendor UI switches from "random color" to "custom color" as soon
        // as the user picks a color: customColorDisabled = 1 means random,
        // 0 means use the custom RGB values.
        update {
            $0.hexColor = mainColor.hexString
            $0.customColorDisabled = 0
        }
    }

    private func updateSideColor() {
        update {
            $0.sideHexColor = sideColor.hexString
            $0.sideCustomColorDisabled = 0
        }
    }

    private func apply() {
        guard let draft else { return }
        store.applyLight(draft)
    }
}
