import SwiftUI

// 主题仅保留浅色默认（深色模式已移除）
struct ThemeConfig {
    let primaryText: Color
    let secondaryText: Color
    let accentColor: Color

    var cardFill: Color { Color.primary.opacity(0.07) }

    var cardStroke: Color { Color.primary.opacity(0.13) }

    static let light = ThemeConfig(
        primaryText: .primary,
        secondaryText: .secondary,
        accentColor: Color(red: 0.85, green: 0.25, blue: 0.25)
    )
}
