import Foundation

enum PinItemType: String, Codable {
    case group, note
}

struct PinItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var type: PinItemType
    var notes: [PinItem] = []   // 仅分组使用
    var text = ""               // 仅便签使用
    var attributedData: Data?   // 正文富文本（NSKeyedArchiver 归档）

    // 文字样式
    var textColor: String?
    var isBold = false
    var isItalic = false
    var fontSize: Double?

    var createdAt = Date()
}
