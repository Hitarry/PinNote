import SwiftUI
import AppKit

enum PillSide {
    case left, right
}

// AppKit 交互层：悬停 / 点击 / 拖拽 全部用原生事件。
// acceptsFirstMouse 保证窗口未激活时首次点击也立即生效（修复“要点 2 次”）
final class PillInteractionView: NSView {
    var itemId: UUID?
    var onTap: (() -> Void)?
    private var startMouse: NSPoint?
    private var lastMouse: NSPoint?
    private var didDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard let itemId else { return }
        NotificationCenter.default.post(name: .pillHoverChanged, object: nil, userInfo: ["id": itemId, "hovering": true])
    }

    override func mouseExited(with event: NSEvent) {
        guard let itemId else { return }
        NotificationCenter.default.post(name: .pillHoverChanged, object: nil, userInfo: ["id": itemId, "hovering": false])
    }

    override func mouseDown(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        startMouse = m
        lastMouse = m
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let itemId else { return }
        let m = NSEvent.mouseLocation
        if let last = lastMouse {
            NotificationCenter.default.post(
                name: .pillDragChanged, object: nil,
                userInfo: ["id": itemId, "dx": Double(m.x - last.x), "dy": Double(m.y - last.y)]
            )
        }
        lastMouse = m
        if let s = startMouse, hypot(m.x - s.x, m.y - s.y) > 4 { didDrag = true }
    }

    override func mouseUp(with event: NSEvent) {
        guard let itemId else { return }
        NotificationCenter.default.post(name: .pillDragEnded, object: nil, userInfo: ["id": itemId])
        if !didDrag { onTap?() }
        startMouse = nil
        lastMouse = nil
        didDrag = false
    }
}

struct PillInteractionRegion: NSViewRepresentable {
    let itemId: UUID
    let onTap: () -> Void

    func makeNSView(context: Context) -> PillInteractionView {
        let view = PillInteractionView()
        view.itemId = itemId
        view.onTap = onTap
        return view
    }

    func updateNSView(_ nsView: PillInteractionView, context: Context) {
        nsView.itemId = itemId
        nsView.onTap = onTap
    }
}

struct PillView: View {
    @Environment(PinNoteViewModel.self) private var vm
    let itemId: UUID
    let side: PillSide

    // 不同便签用不同圆点颜色（按 id 稳定分配）
    private var dotColor: Color {
        let palette: [Color] = [.blue, .red, .green, .orange, .purple, .teal, .pink]
        var hash = 0
        for scalar in itemId.uuidString.unicodeScalars {
            hash = (hash &* 31) &+ Int(scalar.value)
        }
        let index = (hash % palette.count + palette.count) % palette.count
        return palette[index]
    }

    var body: some View {
        let item = vm.findItem(itemId)

        GeometryReader { geo in
            // 胶囊背景/边框直接按窗口实际尺寸绘制（任何尺寸都是椭圆/胶囊），
            // 内容约束在同一尺寸内，避免内容把形状撑大后窗口只显示中间一段矩形
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .frame(width: geo.size.width, height: geo.size.height)
                Capsule()
                    .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                    .frame(width: geo.size.width, height: geo.size.height)

                if geo.size.width <= 40 {
                    // 小胶囊（默认/拖拽）：只显示半个圆 + 蓝色圆点。
                    // 吸附左侧时露右半个圆，圆点放在可见半圆的中心
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .position(x: side == .left ? geo.size.width - 9 : 9, y: geo.size.height / 2)
                } else {
                    // 悬停展开：完整长胶囊 + 圆点 + 标题
                    HStack(spacing: 8) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 8, height: 8)
                        Text(String((item?.text ?? "").prefix(8)).isEmpty ? "便签" : String((item?.text ?? "").prefix(8)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .overlay(
            PillInteractionRegion(itemId: itemId) { vm.exitPillMode(itemId) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}

struct PreviewView: View {
    @Environment(PinNoteViewModel.self) private var vm
    let itemId: UUID

    var body: some View {
        let item = vm.findItem(itemId)

        VStack(alignment: .leading, spacing: 6) {
            Text(String((item?.text ?? "").prefix(20)))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(item?.text.isEmpty == false ? item!.text : "（空便签）")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(6)
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
        .onHover { h in
            NotificationCenter.default.post(name: .previewHoverChanged, object: nil, userInfo: ["id": itemId, "hovering": h])
        }
        .onTapGesture { vm.exitPillMode(itemId) }
    }
}
