import SwiftUI

let pinColors: [(String, String)] = [
    // 黑/灰（5）
    ("#000000", "黑"),("#333333", "灰1"),("#555555", "灰2"),("#888888", "灰3"),("#BBBBBB", "灰4"),
    // 红（5）
    ("#8B0000", "深红"),("#CC0000", "红1"),("#FF0000", "红2"),("#FF3B30", "红3"),("#FF6B6B", "浅红"),
    // 橙（5）
    ("#8B4500", "深橙"),("#CC6600", "橙1"),("#E68A00", "橙2"),("#FF9500", "橙3"),("#FFB347", "浅橙"),
    // 黄（5）
    ("#8B7500", "深黄"),("#B8860B", "金黄"),("#FFCC00", "黄"),("#FFE066", "浅黄"),("#FFF3B0", "极浅黄"),
    // 绿（5）
    ("#006400", "深绿"),("#228B22", "森林绿"),("#34C759", "绿"),("#90EE90", "浅绿"),("#C8E6C9", "极浅绿"),
    // 蓝/青（5）
    ("#00008B", "深蓝"),("#0044FF", "蓝1"),("#007AFF", "蓝2"),("#5AC8FA", "浅蓝"),("#00BCD4", "青"),
    // 紫/粉（5）
    ("#4A007A", "深紫"),("#7B00D4", "紫1"),("#AF52DE", "紫2"),("#FF2D55", "粉"),("#FFA8BE", "浅粉"),
    // 棕（5）
    ("#3E2723", "深棕"),("#6D4C41", "棕"),("#8D6E63", "浅棕"),("#A1887F", "灰棕"),("#D7CCC8", "米棕"),
]

struct EmojiCategory: Identifiable {
    let name: String
    let items: [String]
    var id: String { name }
}

// 精简分类后的常用表情 + 常用标识符号
let emojiCategories: [EmojiCategory] = [
    EmojiCategory(name: "表情", items: [
        "😀","😄","😁","😆","😊","🙂","😉","😍","🥰","😘","😋","😜",
        "🤔","😎","🥳","😴","😅","😂","🤣","😭","😢","😡","😱","😳",
        "🤗","🙃","😌","😏","😮","🥺","😤","😇","🤯","😬","😷","🤒"
    ]),
    EmojiCategory(name: "手势", items: [
        "👍","👎","👌","✌️","🤞","🤟","🤘","👏","🙌","👐","🤝","🙏",
        "💪","👊","✊","🫰","🖐️","✋","👈","👉","👆","👇","🫶","🤙"
    ]),
    EmojiCategory(name: "爱心", items: [
        "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💕","💞","💗",
        "💖","💘","💝","💟","💓","💔","❣️","💫"
    ]),
    EmojiCategory(name: "食物", items: [
        "☕","🍵","🍎","🍊","🍋","🍉","🍇","🍓","🍑","🍒","🥑","🥦",
        "🍔","🍟","🍕","🥪","🍜","🍣","🍦","🍩","🍪","🎂","🍫","🍬"
    ]),
    EmojiCategory(name: "自然", items: [
        "🐶","🐱","🐭","🐰","🦊","🐻","🐼","🐨","🐸","🐮","🐷","🐔",
        "🐧","🐦","🦆","🦉","🐺","🐴","🦄","🐝","🦋","🐌","🌹","🌸",
        "🌺","🌻","🌷","🌿","🍀","☀️","🌙","⭐️","✨","🌈","⚡️","🔥",
        "💧","❄️","🌊"
    ]),
    EmojiCategory(name: "物品", items: [
        "💡","🔔","📌","📍","✂️","🔑","🔒","🔓","📱","💻","⌚️","📸",
        "🎁","🎀","🎈","🎉","🎊","🏆","🥇","🥈","🥉","⚽","🏀","🚀",
        "✈️","🚗","🚲","⛵️","💎","🪄"
    ]),
    EmojiCategory(name: "常用符号", items: [
        "☐","☑","✓","✗","✔","✘","★","☆","♥","♡","●","○",
        "◆","◇","▲","△","▶","►","◀","◄","→","←","↑","↓",
        "↔","§","№","…","·","–","—","“","”","‘","’","※",
        "①","②","③","④","⑤","⑥","⑦","⑧","⑨","⑩","✦","❖",
        "✿","❀","➤","♫","♪"
    ])
]

struct ColorGridPicker: View {
    var selectedHex: String?
    var onSelect: (String?) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5), spacing: 2) {
                ForEach(pinColors, id: \.0) { hex, _ in
                    Button(action: { onSelect(hex) }) {
                        Circle()
                            .fill(colorFromHex(hex))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(selectedHex == hex ? Color.primary : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }
}

struct EmojiGridPicker: View {
    var onInsert: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(emojiCategories) { category in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5), spacing: 2) {
                            ForEach(category.items, id: \.self) { item in
                                Button(action: { onInsert(item) }) {
                                    Text(item).font(.system(size: 15))
                                        .frame(width: 22, height: 22)
                                        .background(Color.primary.opacity(0.04)).cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
    }
}
