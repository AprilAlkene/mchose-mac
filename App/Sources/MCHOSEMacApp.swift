import SwiftUI

@main
struct MCHOSEMacApp: App {
    @StateObject private var store = DeviceStore()

    var body: some Scene {
        WindowGroup("MCHOSE Mac") {
            ContentView(store: store)
        }

        MenuBarExtra("MCHOSE Mac", systemImage: "keyboard") {
            MenuBarContent(store: store)
        }
    }
}
