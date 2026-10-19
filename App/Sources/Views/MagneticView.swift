import SwiftUI
import Features

struct MagneticView: View {
    @ObservedObject var store: DeviceStore

    @State private var selectedIndex = 0
    @State private var draft: TriggerConfig?

    var body: some View {
        Form {
            if store.keymap.isEmpty {
                Text("连接设备后加载磁轴设置")
                    .foregroundStyle(.secondary)
            } else {
                Picker("按键", selection: $selectedIndex) {
                    ForEach(store.keymap) { key in
                        Text("\(key.index)  \(key.name)").tag(key.index)
                    }
                }
                .onChange(of: selectedIndex) { _ in syncDraft() }

                if let trigger = draft {
                    LabeledContent("触发点") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(trigger.keyActuation) / 100.0 },
                                    set: { value in
                                        update { $0.keyActuation = Int((value * 100).rounded()) }
                                    }
                                ),
                                in: 0.1...4.0
                            )
                            Text(String(format: "%.2f mm", Double(trigger.keyActuation) / 100.0))
                                .monospacedDigit()
                                .frame(width: 72, alignment: .trailing)
                        }
                    }

                    LabeledContent("按下 RT") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(trigger.rtPress) / 100.0 },
                                    set: { value in
                                        update { $0.rtPress = Int((value * 100).rounded()) }
                                    }
                                ),
                                in: 0.05...3.0
                            )
                            Text(String(format: "%.2f mm", Double(trigger.rtPress) / 100.0))
                                .monospacedDigit()
                                .frame(width: 72, alignment: .trailing)
                        }
                    }

                    LabeledContent("抬起 RT") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(trigger.rtRelease) / 100.0 },
                                    set: { value in
                                        update { $0.rtRelease = Int((value * 100).rounded()) }
                                    }
                                ),
                                in: 0.05...3.0
                            )
                            Text(String(format: "%.2f mm", Double(trigger.rtRelease) / 100.0))
                                .monospacedDigit()
                                .frame(width: 72, alignment: .trailing)
                        }
                    }
                }

                HStack {
                    Button("应用当前键") { applyCurrent() }
                    Button("应用到全部键") { applyAll() }
                }
                .disabled(store.isBusy || !store.canWrite)
            }
        }
        .padding()
        .onAppear { syncDraft() }
        .onChange(of: store.triggers) { _ in syncDraft() }
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
