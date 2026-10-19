import Foundation
import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(
            in: CharacterSet(charactersIn: "#")
        )
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1.0
        )
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .red
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}
