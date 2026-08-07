import SwiftUI

let pinColors: [(String, String)] = [
    ("#000000", "黑"),("#333333", "灰1"),("#555555", "灰2"),("#777777", "灰3"),("#999999", "灰4"),("#BBBBBB", "灰5"),("#DDDDDD", "灰6"),
    ("#8B0000", "深红"),("#CC0000", "红1"),("#FF0000", "红2"),("#FF3B30", "红3"),("#FF6B6B", "浅红1"),("#FFB5B5", "浅红2"),("#FFD1DC", "浅红3"),
    ("#8B4500", "深橙"),("#CC6600", "橙1"),("#E68A00", "橙2"),("#FF9500", "橙3"),("#FFB347", "浅橙1"),("#FFCC80", "浅橙2"),("#FFD9B3", "浅橙3"),
    ("#8B7500", "深黄"),("#B89A00", "黄1"),("#FFCC00", "黄2"),("#FFE066", "浅黄1"),("#006400", "深绿"),("#34C759", "绿"),("#90EE90", "浅绿"),
    ("#00008B", "深蓝"),("#0044FF", "蓝1"),("#007AFF", "蓝2"),("#80BFFF", "浅蓝1"),("#00695C", "深青"),("#00BCD4", "青"),("#80DEEA", "浅青"),
    ("#4A007A", "深紫"),("#7B00D4", "紫1"),("#AF52DE", "紫2"),("#C47AE8", "浅紫1"),("#8B0040", "深粉"),("#FF2D55", "粉"),("#FFA8BE", "浅粉"),
    ("#3E2723", "深棕"),("#6D4C41", "棕"),("#A1887F", "浅棕"),("#D50000", "亮红"),("#FF6D00", "亮橙"),("#00C853", "亮绿"),("#2962FF", "亮蓝"),
]

let pinEmojis = [
    "😀","😃","😄","😁","😆","😅","😂","🤣","🥲","☺️","😊","😇","🙂","🙃","😉","😌",
    "😍","🥰","😘","😗","😙","😚","😋","😛","😜","🤪","😝","🤑","🤗","🤭","🫢","🫣",
    "🤐","🤨","😐","😑","😶","😏","😒","🙄","😬","😮","😯","😲","😳","🥺","😢","😭",
    "😤","😠","😡","🤯","😱","😨","😰","😥",
    "👍","👎","👊","✊","🤛","🤜","👏","🙌","👐","🤲","🤝","🙏","✌️","🤞","🫰","🤟",
    "🤘","🤙","👈","👉","👆","👇","🖐️","✋","💪","🦵","🦶","👀","👁️","👃","👄","🦷",
    "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💕","💞","💗","💖","💘","💝","💟",
    "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐸","🦁","🐮","🐷","🐒","🐔","🐧",
    "🐦","🐤","🦆","🦅","🦉","🦇","🐺","🐗","🐴","🦄","🐝","🐛","🦋","🐌","🐞","🐜",
    "🌹","🌸","🌺","🌻","🌷","🌿","🍀","🌱",
    "🍎","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍑","🍒","🥑","🥦","🥕","🌽","🧀","☕",
    "🍔","🍟","🌭","🍕","🥪","🥙","🧆","🌮","🌯","🥗","🥘","🍝","🍜","🍲","🍛","🍣",
    "🥟","🍱","🍦","🍩","🍪","🎂","🍫","🍬",
    "💡","🔥","⭐️","✨","🌟","⚡","💧","🌊","🎉","🎊","🎈","🎁","🎀","🪄","🔮","💎",
    "📱","💻","⌚️","📸","🔔","📌","📍","✂️","🔑","🗝️","🔒","🔓","🔐","🛡️","⚔️","🗡️",
    "🏆","🥇","🥈","🥉","⚽","🏀","🏈","⚾",
    "✅","☑️","✔️","❌","❎","➖","➕","➗","➰","〰️","💯","🔝","🔜","🔛","🔙","🔚",
    "♻️","🆗","🆕","🆓","🆙","🆒","🆖","🔞","🛑","⛔","🚫","🚳","🚭","🚯","🚱","📵",
    "🔴","🟠","🟡","🟢","🔵","🟣","🟤","⚫",
    "🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚐","🛴","🚲","🛵","🏍️","🚨","🚔",
    "✈️","🚀","🛸","🚁","🛶","⛵","🚢","🚂",
]

struct ColorGridPicker: View {
    var selectedHex: String?
    var onSelect: (String?) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                Button(action: { onSelect(nil) }) {
                    Circle()
                        .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                        .frame(width: 20, height: 20)
                        .overlay(Text("A").font(.system(size: 9, weight: .medium)))
                }
                .buttonStyle(.plain)
                .help("默认颜色")
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle().fill(Color.clear).frame(width: 20, height: 20).allowsHitTesting(false)
                }
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
            .padding(12)
        }
    }
}

struct EmojiGridPicker: View {
    var onInsert: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(pinEmojis, id: \.self) { emoji in
                    Button(action: { onInsert(emoji) }) {
                        Text(emoji).font(.system(size: 18))
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 28)
                            .background(Color.primary.opacity(0.04)).cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }
}
