import SwiftUI
import AppKit

extension NSColor {
    var hexString: String? {
        guard let c = usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

func colorFromHex(_ hex: String) -> Color {
    var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6, let int = UInt64(h, radix: 16) else { return .primary }
    return Color(
        red: Double((int >> 16) & 0xFF) / 255,
        green: Double((int >> 8) & 0xFF) / 255,
        blue: Double(int & 0xFF) / 255
    )
}
