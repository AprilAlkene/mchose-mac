import SwiftUI
import Features

private struct CommonKey: Identifiable {
    let id: UInt8
    let name: String
}

private let commonKeys: [CommonKey] = [
    .init(id: 41, name: "Esc"),
    .init(id: 43, name: "Tab"),
    .init(id: 44, name: "Space"),
    .init(id: 40, name: "Enter"),
    .init(id: 42, name: "Backspace"),
    .init(id: 4, name: "A"), .init(id: 5, name: "B"), .init(id: 6, name: "C"),
    .init(id: 7, name: "D"), .init(id: 8, name: "E"), .init(id: 9, name: "F"),
    .init(id: 10, name: "G"), .init(id: 11, name: "H"), .init(id: 12, name: "I"),
    .init(id: 13, name: "J"), .init(id: 14, name: "K"), .init(id: 15, name: "L"),
    .init(id: 16, name: "M"), .init(id: 17, name: "N"), .init(id: 18, name: "O"),
    .init(id: 19, name: "P"), .init(id: 20, name: "Q"), .init(id: 21, name: "R"),
    .init(id: 22, name: "S"), .init(id: 23, name: "T"), .init(id: 24, name: "U"),
    .init(id: 25, name: "V"), .init(id: 26, name: "W"), .init(id: 27, name: "X"),
    .init(id: 28, name: "Y"), .init(id: 29, name: "Z"),
    .init(id: 30, name: "1"), .init(id: 31, name: "2"), .init(id: 32, name: "3"),
    .init(id: 33, name: "4"), .init(id: 34, name: "5"), .init(id: 35, name: "6"),
    .init(id: 36, name: "7"), .init(id: 37, name: "8"), .init(id: 38, name: "9"),
    .init(id: 39, name: "0"),
    .init(id: 80, name: "Left"), .init(id: 79, name: "Right"),
    .init(id: 81, name: "Down"), .init(id: 82, name: "Up"),
    .init(id: 76, name: "Delete"),
]

struct KeymapView: View {
    @ObservedObject var store: DeviceStore

    @State private var selectedLayer = 0
    @State private var selectedIndex = 0
    @State private var targetUsage: UInt8 = 41

    private var keys: [KeyInfo] {
        store.keymapLayers[selectedLayer] ?? []
    }

    var body: some View {
        Form {
            Picker("图层", selection: $selectedLayer) {
                ForEach(0..<DeviceMemoryMap.layers, id: \.self) { layer in
                    Text(layerName(layer)).tag(layer)
                }
            }
            .onChange(of: selectedLayer) { layer in
                selectedIndex = 0
                store.loadLayer(layer)
            }

            if keys.isEmpty {
                Text(store.isBusy ? "读取图层…" : "连接设备后加载键位")
                    .foregroundStyle(.secondary)
            } else {
                Picker("按键", selection: $selectedIndex) {
                    ForEach(keys) { key in
                        Text("\(key.index)  \(key.name)").tag(key.index)
                    }
                }

                if selectedIndex < keys.count {
                    LabeledContent("当前映射") {
                        Text(keys[selectedIndex].name)
                    }
                }

                Picker("映射为", selection: $targetUsage) {
                    ForEach(commonKeys) { key in
                        Text(key.name).tag(key.id)
                    }
                }

                Button("应用改键") { apply() }
                    .disabled(store.isBusy || !store.canWrite || selectedIndex >= keys.count)
            }
        }
        .padding()
        .onChange(of: store.keymap) { _ in
            // Re-read the selected layer after a reconnect or profile switch.
            store.loadLayer(selectedLayer)
        }
    }

    private func layerName(_ layer: Int) -> String {
        layer == 0 ? "基础层" : "FN 层 \(layer)"
    }

    private func apply() {
        guard selectedIndex < keys.count else { return }
        var updated = keys
        updated[selectedIndex].type = 16
        updated[selectedIndex].code1 = 0
        updated[selectedIndex].code2 = targetUsage
        updated[selectedIndex].name = KeyNameMap.hidName(targetUsage)
        store.applyKeymap(updated, layer: selectedLayer)
    }
}
