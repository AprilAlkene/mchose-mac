import SwiftUI
import Features

struct LightingView: View {
    @ObservedObject var store: DeviceStore

    @State private var draft: LightConfig?
    @State private var mainColor: Color = .red
    @State private var sideColor: Color = .red

    var body: some View {
        Form {
            if let light = draft {
                Stepper(
                    "主灯效：\(light.effect)",
                    value: Binding(
                        get: { Int(light.effect) },
                        set: { newValue in
                            update { $0.effect = UInt8(clamping: newValue) }
                        }
                    ),
                    in: 0...30
                )

                LabeledContent("主亮度") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(light.brightness) },
                                set: { value in update { $0.brightness = UInt8(clamping: Int(value)) } }
                            ),
                            in: 0...4,
                            step: 1
                        )
                        Text("\(light.brightness) / 4").monospacedDigit()
                    }
                }

                LabeledContent("主速度") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(light.speed) },
                                set: { value in update { $0.speed = UInt8(clamping: Int(value)) } }
                            ),
                            in: 0...4,
                            step: 1
                        )
                        Text("\(light.speed) / 4").monospacedDigit()
                    }
                }

                ColorPicker("主颜色", selection: $mainColor, supportsOpacity: false)
                    .onChange(of: mainColor) { _ in updateColors() }

                LabeledContent("侧灯亮度") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(light.sideBrightness) },
                                set: { value in update { $0.sideBrightness = UInt8(clamping: Int(value)) } }
                            ),
                            in: 0...4,
                            step: 1
                        )
                        Text("\(light.sideBrightness) / 4").monospacedDigit()
                    }
                }

                LabeledContent("侧灯速度") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(light.sideSpeed) },
                                set: { value in update { $0.sideSpeed = UInt8(clamping: Int(value)) } }
                            ),
                            in: 0...4,
                            step: 1
                        )
                        Text("\(light.sideSpeed) / 4").monospacedDigit()
                    }
                }

                ColorPicker("侧灯颜色", selection: $sideColor, supportsOpacity: false)
                    .onChange(of: sideColor) { _ in updateColors() }

                Button("应用灯效") { apply() }
                    .disabled(store.isBusy)
            } else {
                Text("连接设备后加载灯效")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { sync() }
        .onChange(of: store.light) { _ in sync() }
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

    private func updateColors() {
        update {
            $0.hexColor = mainColor.hexString
            $0.sideHexColor = sideColor.hexString
        }
    }

    private func apply() {
        guard let draft else { return }
        store.applyLight(draft)
    }
}
