import Features
import SwiftUI

struct MagneticView: View {
    @ObservedObject var store: DeviceStore

    @State private var selectedIndex = 0
    @State private var draft: TriggerConfig?

    var body: some View {
        PageScroll {
            if store.keymap.isEmpty {
                Card {
                    EmptyState(
                        icon: "slider.horizontal.3",
                        title: "尚未加载磁轴设置",
                        message: store.selected == nil ? "连接设备后可用" : "正在读取设备…"
                    )
                }
            } else {
                Card("按键") {
                    Picker("按键", selection: $selectedIndex) {
                        ForEach(store.keymap) { key in
                            Text("\(key.index)  \(key.name)").tag(key.index)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedIndex) { _ in syncDraft() }
                }

                if let trigger = draft {
                    Card("触发行程") {
                        SettingRow("触发点") {
                            sliderRow(
                                value: Double(trigger.keyActuation) / 100,
                                range: 0.1...4.0,
                                text: String(format: "%.2f mm", Double(trigger.keyActuation) / 100)
                            ) { value in
                                update { $0.keyActuation = Int((value * 100).rounded()) }
                            }
                        }
                        SettingRow("按下 RT") {
                            sliderRow(
                                value: Double(trigger.rtPress) / 100,
                                range: 0.05...5.0,
                                text: String(format: "%.2f mm", Double(trigger.rtPress) / 100)
                            ) { value in
                                update { $0.rtPress = Int((value * 100).rounded()) }
                            }
                        }
                        SettingRow("抬起 RT") {
                            sliderRow(
                                value: Double(trigger.rtRelease) / 100,
                                range: 0.05...5.0,
                                text: String(format: "%.2f mm", Double(trigger.rtRelease) / 100)
                            ) { value in
                                update { $0.rtRelease = Int((value * 100).rounded()) }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("应用到全部键") { applyAll() }
                            .buttonStyle(.bordered)
                        Button("应用当前键") { applyCurrent() }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .disabled(store.isBusy || !store.canWrite)
                }
            }
        }
        .onAppear { syncDraft() }
        .onChange(of: store.triggers) { _ in syncDraft() }
    }

    private func sliderRow(
        value: Double,
        range: ClosedRange<Double>,
        text: String,
        set: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Slider(value: Binding(get: { value }, set: set), in: range)
            Text(text)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
        }
    }

    private func syncDraft() {
        guard selectedIndex < store.triggers.count else {
            draft = nil
            return
        }
        draft = store.triggers[selectedIndex]
    }

    private func update(_ body: (inout TriggerConfig) -> Void) {
        guard var value = draft else { return }
        body(&value)
        draft = value
    }

    private func applyCurrent() {
        guard let value = draft, selectedIndex < store.triggers.count else { return }
        var updated = store.triggers
        updated[selectedIndex] = value
        store.applyTriggers(updated)
    }

    private func applyAll() {
        guard let value = draft else { return }
        var updated = store.triggers
        for index in updated.indices {
            updated[index].keyActuation = value.keyActuation
            updated[index].pressPrecision = value.pressPrecision
            updated[index].releasePrecision = value.releasePrecision
            updated[index].rtPress = value.rtPress
            updated[index].rtRelease = value.rtRelease
            updated[index].pressDeadzone = value.pressDeadzone
            updated[index].releaseDeadzone = value.releaseDeadzone
        }
        store.applyTriggers(updated)
    }
}
