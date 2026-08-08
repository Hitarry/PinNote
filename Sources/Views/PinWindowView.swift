import SwiftUI
import AppKit
import Observation

// 编辑区背景风格
enum EditorBackgroundStyle: String, CaseIterable, Identifiable {
    case blank, dot, lined, grid, cornell

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: return "空白页"
        case .dot: return "点阵页"
        case .lined: return "虚线格"
        case .grid: return "网格本"
        case .cornell: return "木质纹理"
        }
    }
}

// AppKit 原生拖拽区域：鼠标按下拖动直接移动窗口（不依赖 SwiftUI 手势，绝对可靠）
final class WindowDragView: NSView {
    // 拖拽时光标；nil 表示保持系统默认（苹果风格，不显示小手）
    var cursor: NSCursor? = .openHand
    private var startOrigin: NSPoint?
    private var startMouse: NSPoint?

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 24) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startOrigin = window?.frame.origin
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window, let origin = startOrigin, let mouse = startMouse else { return }
        let m = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(x: origin.x + (m.x - mouse.x), y: origin.y + (m.y - mouse.y)))
    }

    override func mouseUp(with event: NSEvent) {
        startOrigin = nil
        startMouse = nil
    }

    override func resetCursorRects() {
        if let cursor {
            addCursorRect(bounds, cursor: cursor)
        }
    }
}

struct WindowDragRegion: NSViewRepresentable {
    var cursor: NSCursor? = .openHand

    func makeNSView(context: Context) -> WindowDragView {
        let view = WindowDragView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: WindowDragView, context: Context) {
        nsView.cursor = cursor
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

// 样式控制器：顶栏样式按钮与正文 NSTextView 选中文本联动
@Observable
final class NoteStyleController {
    @ObservationIgnored weak var textView: NSTextView?

    var colorHex: String? = nil
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var fontSize = 14.0

    private var currentTraits: NSFontDescriptor.SymbolicTraits {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if isBold { traits.insert(.bold) }
        if isItalic { traits.insert(.italic) }
        return traits
    }

    // 只合并本次要改的属性，避免把选中区域里已有的下划线/删除线/颜色等样式清掉
    private func apply(_ attrs: [NSAttributedString.Key: Any]) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            withUndoSnapshot(tv: tv) {
                tv.textStorage?.addAttributes(attrs, range: range)
            }
        }
        tv.typingAttributes.merge(attrs) { _, new in new }
        tv.didChangeText()
        updateFromTextView()
    }

    // 记录修改前的完整富文本，注册撤销；撤销时恢复并注册反向（支持重做）
    private func withUndoSnapshot(tv: NSTextView, _ mutation: () -> Void) {
        guard let storage = tv.textStorage else {
            mutation()
            return
        }
        let old = NSAttributedString(attributedString: storage)
        mutation()
        guard let undo = tv.undoManager else { return }
        undo.registerUndo(withTarget: self) { target in
            target.restoreSnapshot(old, tv: tv)
        }
    }

    private func restoreSnapshot(_ old: NSAttributedString, tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let current = NSAttributedString(attributedString: storage)
        storage.setAttributedString(old)
        tv.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreSnapshot(current, tv: tv)
        }
        tv.didChangeText()
        updateFromTextView()
    }

    private func applyFont(_ traits: NSFontDescriptor.SymbolicTraits) {
        let base = NSFont.systemFont(ofSize: fontSize)
        let font = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: fontSize) ?? base
        apply([.font: font])
    }

    func toggleBold() {
        var traits = currentTraits
        if isBold { traits.remove(.bold) } else { traits.insert(.bold) }
        applyFont(traits)
    }

    func toggleItalic() {
        var traits = currentTraits
        if isItalic { traits.remove(.italic) } else { traits.insert(.italic) }
        applyFont(traits)
    }

    func toggleUnderline() {
        apply([.underlineStyle: isUnderline ? 0 : NSUnderlineStyle.single.rawValue])
    }

    func toggleStrikethrough() {
        apply([.strikethroughStyle: isStrikethrough ? 0 : NSUnderlineStyle.single.rawValue])
    }

    func setFontSize(_ v: Double) {
        fontSize = v
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            // 逐字符按它自己的字体描述符改字号，粗体/斜体等特征天然保留，
            // 完全不依赖按钮状态，杜绝“调字号清粗体”
            var updates: [(NSRange, NSFont)] = []
            storage.enumerateAttribute(.font, in: range, options: []) { font, r, _ in
                let current = (font as? NSFont) ?? NSFont.systemFont(ofSize: 14)
                let sized = NSFont(descriptor: current.fontDescriptor.withSize(v), size: v) ?? current
                updates.append((r, sized))
            }
            withUndoSnapshot(tv: tv) {
                storage.beginEditing()
                for (r, font) in updates.reversed() {
                    storage.addAttribute(.font, value: font, range: r)
                }
                storage.endEditing()
            }
            // 同步打字字体，让按钮显示值与新字号一致
            let loc = min(range.location, max(storage.length - 1, 0))
            let traits = fontTraits(in: storage, location: loc)
            let base = NSFont.systemFont(ofSize: v)
            tv.typingAttributes[.font] = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: v) ?? base
            tv.didChangeText()
            updateFromTextView()
        } else {
            // 光标状态：读取光标前字符的字体特征，只影响后续输入
            let location = max(min(range.location, storage.length - 1), 0)
            let traits = fontTraits(in: storage, location: location)
            let base = NSFont.systemFont(ofSize: v)
            let font = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: v) ?? base
            tv.typingAttributes[.font] = font
            updateFromTextView()
        }
    }

    private func fontTraits(in storage: NSTextStorage, location: Int) -> NSFontDescriptor.SymbolicTraits {
        guard location < storage.length,
              let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont else {
            return []
        }
        return font.fontDescriptor.symbolicTraits
    }

    func setColor(_ hex: String?) {
        let color = hex.flatMap { NSColor(colorFromHex($0)) } ?? NSColor.labelColor
        apply([.foregroundColor: color])
    }

    func resetStyle() {
        guard let tv = textView else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
            .underlineStyle: 0,
            .strikethroughStyle: 0
        ]
        let range = tv.selectedRange()
        if range.length > 0 {
            withUndoSnapshot(tv: tv) {
                tv.textStorage?.beginEditing()
                tv.textStorage?.addAttributes(attrs, range: range)
                // 网页粘贴可能带入背景色（黑底）等属性，addAttributes 覆盖不掉，
                // 重置时显式移除，让“黑块、选中才可见”的文本恢复默认
                tv.textStorage?.removeAttribute(.backgroundColor, range: range)
                tv.textStorage?.removeAttribute(.strokeColor, range: range)
                tv.textStorage?.endEditing()
            }
        }
        tv.typingAttributes = attrs
        tv.didChangeText()
        updateFromTextView()
    }

    func insertEmoji(_ emoji: String) {
        guard let tv = textView else { return }
        tv.insertText(emoji, replacementRange: tv.selectedRange())
        updateFromTextView()
    }

    func updateFromTextView() {
        guard let tv = textView else { return }
        let attrs = tv.typingAttributes
        if let c = attrs[.foregroundColor] as? NSColor { colorHex = c.hexString }
        else { colorHex = nil }
        if let f = attrs[.font] as? NSFont {
            isBold = f.fontDescriptor.symbolicTraits.contains(.bold)
            isItalic = f.fontDescriptor.symbolicTraits.contains(.italic)
            fontSize = f.pointSize
        }
        let underlineValue = (attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0
        isUnderline = underlineValue != 0
        let strikethroughValue = (attrs[.strikethroughStyle] as? NSNumber)?.intValue ?? 0
        isStrikethrough = strikethroughValue != 0
    }
}

struct PinWindowView: View {
    @Environment(PinNoteViewModel.self) private var vm
    let itemId: UUID
    @State private var text = ""
    @State private var styleController = NoteStyleController()
    @State private var showColorPicker = false
    @State private var showEmojiPicker = false
    @State private var editorStyle: EditorBackgroundStyle =
        EditorBackgroundStyle(rawValue: UserDefaults.standard.string(forKey: "editorBackgroundStyle") ?? "") ?? .blank

    var body: some View {
        let theme = ThemeConfig.light
        let item = vm.findItem(itemId)
        let pinned = vm.pinnedItemIds.contains(itemId)

        VStack(spacing: 0) {
            // 顶栏（可拖拽移动窗口，鼠标变小手）
            HStack(spacing: 2) {
                HStack(spacing: 2) {
                    resetBtn
                    styleBtn(Text("B").font(.system(size: 10, weight: .bold)), active: styleController.isBold) { styleController.toggleBold() }
                    styleBtn(Text("I").font(.system(size: 10, weight: .regular)).italic(), active: styleController.isItalic) { styleController.toggleItalic() }
                    styleBtn(Text("U").font(.system(size: 10, weight: .regular)).underline(), active: styleController.isUnderline) { styleController.toggleUnderline() }
                    styleBtn(Text("S").font(.system(size: 10, weight: .regular)).strikethrough(), active: styleController.isStrikethrough) { styleController.toggleStrikethrough() }
                    fontBtn
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.cardFill.opacity(0.5)))

                WindowDragRegion()
                    .frame(maxWidth: .infinity)

                HStack(spacing: 4) {
                    Button(action: { pinned ? vm.unpinItem(itemId) : vm.pinItem(itemId) }) {
                        Image(systemName: pinned ? "pin.slash" : "pin")
                            .font(.system(size: 10))
                            .foregroundColor(pinned ? theme.accentColor : theme.secondaryText)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help(pinned ? "取消钉住" : "钉住")

                    Button(action: { vm.enterPillMode(itemId) }) {
                        Image(systemName: "capsule")
                            .font(.system(size: 10))
                            .foregroundColor(theme.secondaryText)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("胶囊模式（⌘M）")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .fill(theme.secondaryText.opacity(0.15))
                )
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 3)
            .frame(height: 32)

            // 可编辑区域：浅色圆角框标识，不承担拖拽
            NoteTextView(
                text: $text,
                attributedData: item?.attributedData,
                styleController: styleController,
                backgroundStyle: editorStyle,
                onAttributedChange: { plain, data in
                    vm.updateAttributedText(itemId, plain, data)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 3)
            .padding(.bottom, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.secondaryText.opacity(0.18), lineWidth: 1)
                    .padding(3)
            )

            // 底栏：实时字符数 + 颜色/表情/背景样式 + 拖拽移动（系统默认光标）+ 右下角缩放提示
            HStack(spacing: 4) {
                Text("\(text.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.secondaryText.opacity(0.6))
                    .padding(.leading, 6)
                    .help("编辑框字符数")

                colorBtn
                emojiBtn
                editorStyleMenu

                WindowDragRegion(cursor: nil)
                    .frame(maxWidth: .infinity)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.secondaryText.opacity(0.5))
                    .padding(6)
                    .allowsHitTesting(false)
                    .help("拖动窗口边缘调整大小")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 1)
            .frame(height: 20)
        }
        .frame(minWidth: 240, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .onAppear {
            text = vm.findItem(itemId)?.text ?? ""
        }
        .background {
            // ⌘M：悬浮窗模式一键切换到胶囊吸附模式
            Button("") { vm.enterPillMode(itemId) }
                .keyboardShortcut("m", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }

    // MARK: - 顶栏样式按钮

    private func styleBtn<Label: View>(_ label: Label, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .frame(width: 18, height: 18)
                .background(active ? Color.accentColor.opacity(0.22) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var fontBtn: some View {
        Menu {
            ForEach([8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 32, 36, 48, 72], id: \.self) { size in
                Button {
                    styleController.setFontSize(Double(size))
                } label: {
                    if Int(styleController.fontSize) == size {
                        Label("\(size)", systemImage: "checkmark")
                    } else {
                        Text("\(size)")
                    }
                }
            }
        } label: {
            Text("A\(Int(styleController.fontSize))")
                .font(.system(size: 9, weight: .medium))
                .frame(width: 30, height: 18)
                .background(styleController.fontSize != 14 ? Color.accentColor.opacity(0.22) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("字号（下拉选择）")
    }

    private var colorBtn: some View {
        Button(action: { showColorPicker = true }) {
            Circle()
                // 未设置颜色时显示默认文字色（浅色模式黑色），而不是灰色占位
                .fill(styleController.colorHex.map(colorFromHex) ?? Color.primary)
                .frame(width: 12, height: 12)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            ColorGridPicker(selectedHex: styleController.colorHex) { styleController.setColor($0) }
                .frame(width: 145, height: 205)
        }
    }

    private var resetBtn: some View {
        Button(action: { styleController.resetStyle() }) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help("恢复默认样式")
    }

    private var emojiBtn: some View {
        Button(action: { showEmojiPicker = true }) {
            Image(systemName: "face.smiling")
                .font(.system(size: 11))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help("插入表情")
        .popover(isPresented: $showEmojiPicker, arrowEdge: .bottom) {
            EmojiGridPicker { styleController.insertEmoji($0) }
                .frame(width: 160, height: 230)
        }
    }

    private var editorStyleMenu: some View {
        Menu {
            ForEach(EditorBackgroundStyle.allCases) { style in
                Button {
                    editorStyle = style
                    UserDefaults.standard.set(style.rawValue, forKey: "editorBackgroundStyle")
                } label: {
                    if style == editorStyle {
                        Label(style.displayName, systemImage: "checkmark")
                    } else {
                        Text(style.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundColor(ThemeConfig.light.secondaryText)
                .frame(width: 18, height: 18)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("编辑区背景")
    }

    // MARK: - 拖拽 / 缩放（基于全局鼠标位置，杜绝抖动）

}

// 编辑区背景纸样（AppKit 绘制，放在滚动视图内容下方）
final class NoteBackgroundView: NSView {
    var style: EditorBackgroundStyle = .blank {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    // 每种风格用不同的纸张底色（都很浅）
    private func paperColor(for style: EditorBackgroundStyle) -> NSColor {
        switch style {
        case .blank: return .white
        case .dot: return NSColor(calibratedRed: 0.996, green: 0.984, blue: 0.95, alpha: 1)    // 极浅米白
        case .lined: return NSColor(calibratedRed: 0.996, green: 0.986, blue: 0.95, alpha: 1)  // 极浅米黄
        case .grid: return NSColor(calibratedWhite: 0.99, alpha: 1)                            // 近白
        case .cornell: return NSColor(calibratedRed: 0.98, green: 0.94, blue: 0.84, alpha: 1)  // 浅木色
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        paperColor(for: style).setFill()
        bounds.fill()

        switch style {
        case .blank:
            break
        case .dot:
            // 点阵：更小更浅的圆点
            let spacing: CGFloat = 20
            NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
            var x: CGFloat = 10
            while x <= bounds.maxX {
                var y: CGFloat = 10
                while y <= bounds.maxY {
                    NSBezierPath(ovalIn: NSRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)).fill()
                    y += spacing
                }
                x += spacing
            }
        case .lined:
            // 虚线格：格子大一些、线细且浅
            let spacing: CGFloat = 36
            let path = NSBezierPath()
            path.lineWidth = 0.6
            path.setLineDash([4, 5], count: 2, phase: 0)
            NSColor(calibratedWhite: 0.80, alpha: 1).setStroke()
            var x: CGFloat = spacing
            while x <= bounds.maxX {
                path.move(to: NSPoint(x: x, y: 0))
                path.line(to: NSPoint(x: x, y: bounds.maxY))
                x += spacing
            }
            var y: CGFloat = spacing
            while y <= bounds.maxY {
                path.move(to: NSPoint(x: 0, y: y))
                path.line(to: NSPoint(x: bounds.maxX, y: y))
                y += spacing
            }
            path.stroke()
        case .grid:
            // 网格本：更细更浅
            let path = NSBezierPath()
            path.lineWidth = 0.6
            NSColor(calibratedWhite: 0.85, alpha: 1).setStroke()
            let spacing: CGFloat = 20
            var x: CGFloat = spacing
            while x <= bounds.maxX {
                path.move(to: NSPoint(x: x, y: 0))
                path.line(to: NSPoint(x: x, y: bounds.maxY))
                x += spacing
            }
            var y: CGFloat = spacing
            while y <= bounds.maxY {
                path.move(to: NSPoint(x: 0, y: y))
                path.line(to: NSPoint(x: bounds.maxX, y: y))
                y += spacing
            }
            path.stroke()
        case .cornell:
            // 木质纹理：浅木色底 + 细木纹曲线
            let grain = NSColor(calibratedRed: 0.72, green: 0.58, blue: 0.38, alpha: 0.30)
            grain.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 0.8
            var y: CGFloat = 16
            let step: CGFloat = 24
            while y <= bounds.maxY {
                path.move(to: NSPoint(x: 0, y: y))
                var x: CGFloat = 0
                var phase: CGFloat = 0
                while x <= bounds.maxX {
                    let nx = x + 44
                    let ny = y + sin(phase) * 3
                    path.curve(
                        to: NSPoint(x: nx, y: ny),
                        controlPoint1: NSPoint(x: x + 15, y: y + 4),
                        controlPoint2: NSPoint(x: x + 29, y: y - 4)
                    )
                    x = nx
                    phase += .pi / 2
                }
                y += step
            }
            path.stroke()
        }
    }
}

// 粘贴拦截：网页/搜索框复制的富文本常带背景色（黑底）或浅色前景（白字），
// 在浅色纸上看不见、只有选中才可见；粘贴前统一清洗后再插入
final class PinNoteTextView: NSTextView {
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let type = pb.availableType(from: [.rtfd, .rtf, .html]),
              let data = pb.data(forType: type),
              let attr = attributedString(from: data, type: type) else {
            super.paste(sender)
            return
        }
        let sanitized = sanitizePastedText(attr)
        if sanitized.isEqual(to: attr) {
            super.paste(sender)
        } else {
            insertText(sanitized, replacementRange: selectedRange())
        }
    }

    override func pasteAsRichText(_ sender: Any?) {
        paste(sender)
    }

    private func attributedString(from data: Data, type: NSPasteboard.PasteboardType) -> NSAttributedString? {
        switch type {
        case .rtf:
            return try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        case .rtfd:
            return try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            )
        case .html:
            return try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
        default:
            return nil
        }
    }
}

struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    var attributedData: Data?
    var styleController: NoteStyleController?
    var backgroundStyle: EditorBackgroundStyle = .blank
    var onAttributedChange: (String, Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = PinNoteTextView()
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 8)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = context.coordinator
        tv.string = text

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let background = NoteBackgroundView()
        background.style = backgroundStyle
        background.autoresizingMask = [.width]
        // 放进 clip view 内、文档视图下方：clip view 自身不透明背景不会盖住它
        scroll.contentView.addSubview(background, positioned: .below, relativeTo: tv)
        scroll.contentView.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = true
        tv.postsFrameChangedNotifications = true

        if let data = attributedData,
           let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
            // 关闭安全解码：自定义勾选框附件类需要按 NSCoding 解码
            unarchiver.requiresSecureCoding = false
            if let att = unarchiver.decodeObject(of: NSAttributedString.self, forKey: NSKeyedArchiveRootObjectKey) {
                tv.textStorage?.setAttributedString(att)
            }
        }
        // 默认字体 14pt（NSTextView 默认是 Helvetica 12），与重置/显示值保持一致
        tv.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]
        styleController?.textView = tv
        styleController?.updateFromTextView()
        syncEditorBackground(scroll)
        // 滚动、文本增长、窗口缩放时都让背景纸样跟随文档尺寸，
        // 避免一直回车后下方区域没有背景覆盖（纯白）
        context.coordinator.boundsToken = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView,
            queue: .main
        ) { [weak scroll] _ in
            if let scroll { syncEditorBackground(scroll) }
        }
        context.coordinator.frameToken = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: tv,
            queue: .main
        ) { [weak scroll] _ in
            if let scroll { syncEditorBackground(scroll) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard scroll.documentView is NSTextView else { return }
        for subview in scroll.contentView.subviews {
            if let background = subview as? NoteBackgroundView, background.style != backgroundStyle {
                background.style = backgroundStyle
            }
        }
        syncEditorBackground(scroll)
        // 注意：text 只由文本视图自身的 textDidChange 回写，二者始终一致，
        // 这里绝不能用 tv.string = text 做“同步”，否则会用纯文本整段覆盖、
        // 清掉已设置的富文本样式（下划线/删除线/颜色等）
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let token = coordinator.boundsToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = coordinator.frameToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        var boundsToken: NSObjectProtocol?
        var frameToken: NSObjectProtocol?
        init(_ parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            notifyChange(tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.styleController?.updateFromTextView()
        }

        func notifyChange(_ tv: NSTextView) {
            let data = try? NSKeyedArchiver.archivedData(
                withRootObject: tv.textStorage ?? NSAttributedString(),
                requiringSecureCoding: false
            )
            parent.onAttributedChange(tv.string, data)
        }
    }
}

// 让编辑区背景纸样始终覆盖整个文档（含滚动后新露出的区域）
private func syncEditorBackground(_ scroll: NSScrollView) {
    guard let tv = scroll.documentView as? NSTextView else { return }
    let size = NSSize(
        width: max(scroll.contentSize.width, tv.frame.width),
        height: max(scroll.contentSize.height, tv.frame.height)
    )
    for subview in scroll.contentView.subviews {
        if let background = subview as? NoteBackgroundView {
            background.frame = NSRect(origin: .zero, size: size)
            background.needsDisplay = true
        }
    }
}

// 清洗粘贴进来的富文本：
// 1) 去掉字符背景色（网页高亮/黑底复制的主要来源）
// 2) 前景色太浅（白字、浅灰、半透明等）时恢复默认黑，保证在浅色纸上可读
private func sanitizePastedText(_ input: NSAttributedString) -> NSAttributedString {
    let output = NSMutableAttributedString(attributedString: input)
    output.beginEditing()
    output.enumerateAttributes(in: NSRange(location: 0, length: output.length), options: []) { attrs, range, _ in
        var cleaned = attrs
        let hadBackground = cleaned.removeValue(forKey: .backgroundColor) != nil
        if let color = cleaned[.foregroundColor] as? NSColor,
           isHardToReadOnPaper(color, hadBackground: hadBackground) {
            cleaned[.foregroundColor] = NSColor.black
        }
        output.setAttributes(cleaned, range: range)
    }
    output.endEditing()
    return output
}

// 文字在浅色纸（白/米白）背景上是否难以辨认：
// - 很浅的近中性色（白、浅灰等）直接视为不可见
// - 半透明前景在浅色纸上也看不清
// - 原本带背景色一起粘贴时，前景只要偏浅就改为默认黑（白字黑底的典型情况）
private func isHardToReadOnPaper(_ color: NSColor, hadBackground: Bool) -> Bool {
    guard let rgb = color.usingColorSpace(.sRGB) else { return false }
    let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
    if rgb.alphaComponent < 0.5 { return true }
    let luminance = 0.299 * r + 0.587 * g + 0.114 * b
    let saturation = max(r, g, b) - min(r, g, b)
    if luminance > 0.80 && saturation < 0.22 { return true }
    if hadBackground && luminance > 0.80 { return true }
    return false
}
