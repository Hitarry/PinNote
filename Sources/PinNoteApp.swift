import SwiftUI
import AppKit
import QuartzCore

extension Notification.Name {
    static let openNoteWindow = Notification.Name("openNoteWindow")
    static let closePopoverShortcut = Notification.Name("closePopoverShortcut")
    static let pillHoverChanged = Notification.Name("pillHoverChanged")
    static let previewHoverChanged = Notification.Name("previewHoverChanged")
    static let menuCardHoverChanged = Notification.Name("menuCardHoverChanged")
    static let pillDragChanged = Notification.Name("pillDragChanged")
    static let pillDragEnded = Notification.Name("pillDragEnded")
}

@main
struct PinNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        _ = PinNoteViewModel.shared
    }

    var body: some Scene {
        Settings { }
    }
}

final class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var noteWindows: [UUID: NSWindow] = [:]
    private var noteFrames: [UUID: NSRect] = [:]   // 记住每个便签悬浮窗上次的位置/大小
    private var windowUndoManagers: [ObjectIdentifier: UndoManager] = [:]
    private var pillWindows: [UUID: NSWindow] = [:]
    private var pillDotColorIndices: [UUID: Int] = [:]
    private var previewPanels: [UUID: NSPanel] = [:]
    private var menuPreviewPanel: NSPanel?
    private var previewHover: Set<UUID> = []
    private var pillEdges: [UUID: Edge] = [:]
    private var pillAnchors: [UUID: NSPoint] = [:]
    private var pillDragShrunk: Set<UUID> = []
    private var pillDragging: Set<UUID> = []
    private var pillWasDragged: Set<UUID> = []
    private var pillExpanded: Set<UUID> = []
    private var pendingHideTimers: [UUID: DispatchWorkItem] = [:]
    private var pendingPreviewTimers: [UUID: DispatchWorkItem] = [:]
    private var pendingCollapseTimers: [UUID: DispatchWorkItem] = [:]

    enum Edge { case left, right, top, bottom }

    // 胶囊圆点配色：12 种鲜艳颜色（不饱和色过淡、看不清）
    private let pillColorPalette: [Color] = [
        .blue, .red, .green, .orange, .purple, .teal,
        .pink, .yellow, .brown, .indigo, .cyan, .mint
    ]

    // 每个同时吸附的胶囊分配不同的圆点颜色：以 id 哈希为基准，冲突时顺延到下一个空闲色
    private func pillDotColor(for id: UUID) -> Color {
        if let index = pillDotColorIndices[id] {
            return pillColorPalette[index % pillColorPalette.count]
        }
        var hash = 0
        for scalar in id.uuidString.unicodeScalars {
            hash = (hash &* 31) &+ Int(scalar.value)
        }
        var index = (hash % pillColorPalette.count + pillColorPalette.count) % pillColorPalette.count
        let used = Set(pillDotColorIndices.values)
        var guardCount = 0
        while used.contains(index), guardCount < pillColorPalette.count {
            index = (index + 1) % pillColorPalette.count
            guardCount += 1
        }
        pillDotColorIndices[id] = index
        return pillColorPalette[index]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()

        let vm = PinNoteViewModel.shared
        vm.onPinChanged = { [weak self] id, isPin in
            if isPin { self?.showNoteWindow(for: id) }
            else { self?.hideNoteWindow(for: id) }
        }
        vm.onPillChanged = { [weak self] id, isPill in
            if isPill { self?.showPillWindow(for: id) }
            else { self?.hidePillWindow(for: id) }
        }
        for id in vm.pinnedItemIds { vm.onPinChanged?(id, true) }
        for id in vm.pillItemIds { vm.onPillChanged?(id, true) }

        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenNote), name: .openNoteWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closePopover), name: .closePopoverShortcut, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pillHover(_:)), name: .pillHoverChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(previewHover(_:)), name: .previewHoverChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuCardHover(_:)), name: .menuCardHoverChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pillDragChanged(_:)), name: .pillDragChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pillDragEnded(_:)), name: .pillDragEnded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(redrawPillWindows), name: NSWindow.didResizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(redrawPillWindows), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func redrawPillWindows() {
        for win in pillWindows.values {
            win.contentView?.needsDisplay = true
        }
    }

    // MARK: - 状态栏

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: -1)
        statusItem = item

        if let button = item.button {
            let image = generateMenuBarIcon()
            image.isTemplate = true
            button.image = image
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let p = NSPopover()
        p.behavior = .transient
        p.delegate = self
        popover = p
    }

    private func generateMenuBarIcon() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size)
        image.lockFocus()

        // 圆角矩形边框
        let border = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 17, height: 17), xRadius: 4, yRadius: 4)
        border.lineWidth = 1.4
        NSColor.black.setStroke()
        border.stroke()

        let lineYs: [CGFloat] = [6.0, 10, 14.0]
        let x0: CGFloat = 5.0
        let x1: CGFloat = 14.5
        let dotR: CGFloat = 1.7

        for y in lineYs {
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: x0 - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)).fill()
            let line = NSBezierPath()
            line.lineWidth = 1.4
            line.move(to: NSPoint(x: x0 + dotR, y: y))
            line.line(to: NSPoint(x: x1, y: y))
            line.stroke()
        }

        image.unlockFocus()
        return image
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "退出 PinNote", action: #selector(quitApp), keyEquivalent: "q"))
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 5), in: sender)
        } else {
            togglePopover()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func showPopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environment(PinNoteViewModel.shared)
        )
        popover.contentSize = NSSize(width: 268, height: 435)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    @objc private func closePopover() {
        guard let popover = popover, popover.isShown else { return }
        popover.performClose(nil)
    }

    // MARK: - 便签悬浮窗

    @objc private func handleOpenNote(_ notification: Notification) {
        guard let id = notification.userInfo?["id"] as? UUID else { return }
        closePopover()
        hideMenuPreview()
        let vm = PinNoteViewModel.shared
        vm.exitPillMode(id)
        vm.pinItem(id)
        showNoteWindow(for: id)
    }

    private func showNoteWindow(for id: UUID) {
        guard !PinNoteViewModel.shared.pillItemIds.contains(id) else { return }
        if let win = noteWindows[id] {
            win.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: PinWindowView(itemId: id).environment(PinNoteViewModel.shared)
        )
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        let win = NoteWindow(contentViewController: hosting)
        win.styleMask = [.fullSizeContentView, .resizable]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.isMovableByWindowBackground = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.contentMinSize = NSSize(width: 240, height: 300)
        win.contentMaxSize = NSSize(width: 900, height: 1000)

        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let saved = noteFrames[id] {
            // 取消钉住 / 胶囊退出后重新打开：恢复上次编辑调整后的位置和大小
            var size = saved.size
            size.width = min(max(size.width, 240), 900)
            size.height = min(max(size.height, 300), 1000)
            win.setContentSize(size)
            var origin = saved.origin
            origin.x = min(max(origin.x, visible.minX - size.width + 80), visible.maxX - 80)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
            win.setFrameOrigin(origin)
        } else {
            // 初次钉住：屏幕左侧、最小尺寸、距左边缘留 16px 间距
            win.setContentSize(NSSize(width: 240, height: 300))
            let offset = CGFloat(noteWindows.count) * 26
            win.setFrameOrigin(NSPoint(
                x: visible.minX + 16,
                y: min(visible.minY + 60 + offset, visible.maxY - 300)
            ))
        }
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        noteWindows[id] = win
    }

    private func hideNoteWindow(for id: UUID) {
        if let win = noteWindows[id] {
            noteFrames[id] = win.frame
            windowUndoManagers.removeValue(forKey: ObjectIdentifier(win))
            win.close()
        }
        noteWindows[id] = nil
    }

    // 无边框窗口默认没有 undoManager，需要由 delegate 提供，否则 ⌘Z 无效
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        let key = ObjectIdentifier(window)
        if let manager = windowUndoManagers[key] {
            return manager
        }
        let manager = UndoManager()
        windowUndoManagers[key] = manager
        return manager
    }

    // MARK: - 胶囊模式

    private func showPillWindow(for id: UUID) {
        // 有上次拖拽后的吸附记录则恢复它；否则按悬浮窗当前位置决定吸附侧
        let edge: Edge
        if pillAnchors[id] != nil, let remembered = pillEdges[id] {
            edge = remembered
        } else {
            edge = attachEdge(for: id)
        }
        pillEdges[id] = edge
        let dotColor = pillDotColor(for: id)
        hideNoteWindow(for: id)
        hidePreview(for: id)
        guard pillWindows[id] == nil else { return }

        let hosting = NSHostingController(
            rootView: PillView(itemId: id, side: edge == .left ? .left : .right, dotColor: dotColor)
                .environment(PinNoteViewModel.shared)
        )
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        let win = NoteWindow(contentViewController: hosting)
        win.styleMask = [.fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.isMovableByWindowBackground = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let size = NSSize(width: 30, height: 26)
        win.contentMinSize = size
        win.contentMaxSize = size
        win.setContentSize(size)
        win.contentView?.wantsLayer = true

        attachPill(win, for: id)
        win.orderFront(nil)
        pillWindows[id] = win
    }

    private func hidePillWindow(for id: UUID) {
        pendingHideTimers[id]?.cancel()
        pendingPreviewTimers[id]?.cancel()
        pendingCollapseTimers[id]?.cancel()
        hidePreview(for: id)
        pillDotColorIndices.removeValue(forKey: id)
        pillWindows[id]?.close()
        pillWindows[id] = nil
        pillDragging.remove(id)
        pillExpanded.remove(id)
        if PinNoteViewModel.shared.pinnedItemIds.contains(id) {
            showNoteWindow(for: id)
        }
    }

    private func attachPill(_ win: NSWindow, for id: UUID) {
        let v = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let s = win.frame.size
        let edge = pillEdges[id] ?? .left
        pillEdges[id] = edge

        var anchorY: CGFloat
        if pillWasDragged.contains(id), let remembered = pillAnchors[id] {
            // 只有用户拖拽过的胶囊恢复上次位置；未拖拽的默认胶囊始终重新分布，避免互相重叠
            anchorY = min(max(remembered.y, v.minY), v.maxY - s.height)
        } else {
            // 首次：垂直分布，多个胶囊上下间距 64，防止悬停/预览互相误触
            let ids = PinNoteViewModel.shared.pillItemIds.sorted { $0.uuidString < $1.uuidString }
            let idx = ids.firstIndex(of: id) ?? 0
            let total = max(ids.count, 1)
            anchorY = v.midY - CGFloat(total - 1) * 32 + CGFloat(idx) * 64 - s.height / 2
        }

        let anchor: NSPoint
        switch edge {
        case .left:
            anchor = NSPoint(x: v.minX - s.width + 18, y: anchorY)
        case .right:
            anchor = NSPoint(x: v.maxX - 18, y: anchorY)
        case .top:
            anchor = NSPoint(x: v.midX - s.width / 2, y: v.maxY - 13)
        case .bottom:
            anchor = NSPoint(x: v.midX - s.width / 2, y: v.minY - s.height + 13)
        }
        win.setFrameOrigin(anchor)
        pillAnchors[id] = anchor
        win.contentView?.needsDisplay = true
    }

    private func attachEdge(for id: UUID) -> Edge {
        let v = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let note = noteWindows[id] {
            // 按悬浮窗中心所在的半屏决定吸附侧
            return note.frame.midX < v.midX ? .left : .right
        }
        // 无悬浮窗（菜单栏直接进胶囊 / 启动恢复）：默认吸附左侧
        return .left
    }

    // MARK: - 胶囊悬停预览

    @objc private func pillHover(_ notification: Notification) {
        guard let info = notification.userInfo,
              let id = info["id"] as? UUID,
              let hovering = info["hovering"] as? Bool else { return }
        guard !pillDragging.contains(id) else { return }
        if hovering {
            pendingHideTimers[id]?.cancel()
            pendingCollapseTimers[id]?.cancel()
            if !pillExpanded.contains(id) {
                pillExpanded.insert(id)
                animatePill(id, reveal: true)
            }
            if previewPanels[id] == nil {
                let work = DispatchWorkItem { [weak self] in self?.showPreview(for: id) }
                pendingPreviewTimers[id] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            }
        } else {
            pendingPreviewTimers[id]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.previewHover.contains(id) else { return }
                self.pillExpanded.remove(id)
                self.pendingPreviewTimers[id]?.cancel()
                self.hidePreview(for: id)
                self.animatePill(id, reveal: false)
            }
            pendingCollapseTimers[id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    private func animatePill(_ id: UUID, reveal: Bool) {
        guard let win = pillWindows[id], let edge = pillEdges[id] else { return }
        let v = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = reveal ? NSSize(width: 140, height: 48) : NSSize(width: 30, height: 26)
        let origin: NSPoint
        switch edge {
        case .left:
            origin = NSPoint(x: v.minX - size.width + (reveal ? size.width : 18), y: win.frame.minY)
        case .right:
            origin = NSPoint(x: v.maxX - (reveal ? size.width : 18), y: win.frame.minY)
        case .top:
            origin = NSPoint(x: win.frame.minX, y: v.maxY - (reveal ? size.height : 13))
        case .bottom:
            origin = NSPoint(x: win.frame.minX, y: v.minY - size.height + (reveal ? size.height : 13))
        }
        win.contentMinSize = size
        win.contentMaxSize = size
        win.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
        pillAnchors[id] = origin
        win.contentView?.needsDisplay = true
    }

    @objc private func pillDragChanged(_ notification: Notification) {
        guard let info = notification.userInfo,
              let id = info["id"] as? UUID,
              let dx = info["dx"] as? Double,
              let dy = info["dy"] as? Double,
              let win = pillWindows[id] else { return }
        pillDragging.insert(id)
        pendingPreviewTimers[id]?.cancel()
        pendingCollapseTimers[id]?.cancel()
        pillExpanded.remove(id)
        hidePreview(for: id)
        // 拖拽时缩成 25px 小椭圆
        if !pillDragShrunk.contains(id) {
            pillDragShrunk.insert(id)
            let old = win.frame
            win.contentMinSize = NSSize(width: 30, height: 26)
            win.contentMaxSize = NSSize(width: 30, height: 26)
            win.setFrame(NSRect(x: old.midX - 15, y: old.midY - 13, width: 30, height: 26), display: true)
            win.contentView?.layoutSubtreeIfNeeded()
            win.contentView?.needsDisplay = true
        }
        win.setFrameOrigin(NSPoint(x: win.frame.minX + dx, y: win.frame.minY + dy))
    }

    @objc private func pillDragEnded(_ notification: Notification) {
        guard let id = notification.userInfo?["id"] as? UUID, let win = pillWindows[id] else { return }
        // 标记为用户拖拽过，之后重建胶囊时恢复该位置
        pillWasDragged.insert(id)
        pillDragShrunk.remove(id)
        pillDragging.remove(id)
        pillExpanded.remove(id)
        pendingPreviewTimers[id]?.cancel()
        pendingCollapseTimers[id]?.cancel()
        hidePreview(for: id)

        let v = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let f = win.frame
        // 松手后按所在半区吸附，不留在屏幕中间
        let edge: Edge = f.midX < v.midX ? .left : .right
        pillEdges[id] = edge
        let anchor = edge == .left
            ? NSPoint(x: v.minX - f.width + 18, y: f.minY)
            : NSPoint(x: v.maxX - 18, y: f.minY)
        win.setFrameOrigin(anchor)
        pillAnchors[id] = anchor
    }

    // MARK: - 菜单栏卡片悬停预览

    @objc private func menuCardHover(_ notification: Notification) {
        guard let info = notification.userInfo,
              let id = info["id"] as? UUID,
              let hovering = info["hovering"] as? Bool else { return }
        if hovering { showMenuPreview(for: id) }
        else { hideMenuPreview() }
    }

    private func showMenuPreview(for id: UUID) {
        hideMenuPreview()
        let hosting = NSHostingController(
            rootView: PreviewView(itemId: id).environment(PinNoteViewModel.shared)
        )
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.nonactivatingPanel, .borderless]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let size = NSSize(width: 262, height: 190)
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.setContentSize(size)
        if let pv = popover?.contentViewController?.view.window {
            panel.setFrameOrigin(NSPoint(x: pv.frame.maxX + 8, y: pv.frame.midY - size.height / 2))
        }
        panel.orderFront(nil)
        menuPreviewPanel = panel
    }

    private func hideMenuPreview() {
        menuPreviewPanel?.close()
        menuPreviewPanel = nil
    }

    @objc private func previewHover(_ notification: Notification) {
        guard let info = notification.userInfo,
              let id = info["id"] as? UUID,
              let hovering = info["hovering"] as? Bool else { return }
        if hovering {
            previewHover.insert(id)
            pendingCollapseTimers[id]?.cancel()
            pillExpanded.insert(id)
            animatePill(id, reveal: true)
        } else {
            previewHover.remove(id)
            pendingHideTimers[id]?.cancel()
            hidePreview(for: id)
            pendingCollapseTimers[id]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pillExpanded.remove(id)
                self.animatePill(id, reveal: false)
            }
            pendingCollapseTimers[id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    private func showPreview(for id: UUID) {
        guard pillWindows[id] != nil, previewPanels[id] == nil else { return }
        let hosting = NSHostingController(
            rootView: PreviewView(itemId: id).environment(PinNoteViewModel.shared)
        )
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.nonactivatingPanel, .borderless]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let size = NSSize(width: 262, height: 190)
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.setContentSize(size)

        if let pill = pillWindows[id], let edge = pillEdges[id] {
            let pf = pill.frame
            var origin = pf.origin
            switch edge {
            case .left: origin = NSPoint(x: pf.maxX + 8, y: pf.midY - size.height / 2)
            case .right: origin = NSPoint(x: pf.minX - size.width - 8, y: pf.midY - size.height / 2)
            case .top: origin = NSPoint(x: pf.midX - size.width / 2, y: pf.minY - size.height - 8)
            case .bottom: origin = NSPoint(x: pf.midX - size.width / 2, y: pf.maxY + 8)
            }
            panel.setFrameOrigin(origin)
        }
        panel.orderFront(nil)
        previewPanels[id] = panel
    }

    private func hidePreview(for id: UUID) {
        previewPanels[id]?.close()
        previewPanels[id] = nil
        previewHover.remove(id)
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        for (id, w) in noteWindows where w === win {
            if !PinNoteViewModel.shared.pinnedItemIds.contains(id) {
                hideNoteWindow(for: id)
            }
            break
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    func popoverDidClose(_ notification: Notification) {
        if notification.object as? NSPopover == popover {
            popover?.contentViewController = nil
            hideMenuPreview()
        }
    }
}
