import SwiftUI

struct PinCardView: View {
    @Environment(PinNoteViewModel.self) private var vm
    let itemId: UUID
    var dropGroupId: UUID? = nil
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var isHovering = false
    @State private var tapPulse = false
    @State private var showDeleteConfirm = false

    var body: some View {
        let _ = vm.sortStamp
        let theme = ThemeConfig.light
        let item = vm.findItem(itemId)
        let isGroup = item?.type == .group
        let titleText = isGroup ? (item?.title ?? "") : String((item?.text ?? "").prefix(12))

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if isGroup {
                    Button(action: { vm.toggleCollapseGroup(itemId) }) {
                        Image(systemName: vm.collapsedGroupIds.contains(itemId) ? "chevron.right" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.secondaryText)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText.opacity(0.5))
                }

                if isEditing && isGroup {
                    TextField("分组名", text: $editingText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .onSubmit { commit() }
                        .onChange(of: isEditing) { _, v in if !v && isGroup { commit() } }
                } else {
                    Text(titleText.isEmpty ? (isGroup ? "（未命名）" : "（空便签）") : titleText)
                        .font(.system(size: isGroup ? 12 : 12))
                        .fontWeight(isGroup ? .semibold : .regular)
                        .foregroundColor(isGroup ? theme.primaryText : (item?.textColor).map(colorFromHex) ?? theme.primaryText)
                        .lineLimit(1)
                        .onTapGesture {
                            if isGroup {
                                isEditing = true
                                editingText = item?.title ?? ""
                            }
                        }
                }

                Spacer()

                if isGroup {
                    Button(action: { vm.addNote(to: itemId) }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(theme.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("在分组下新建便签")
                } else {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(theme.secondaryText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("删除便签")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            if isGroup, let item = item, !vm.collapsedGroupIds.contains(itemId), !item.notes.isEmpty {
                VStack(spacing: 4) {
                    ForEach(vm.sortedGroupNotes(item)) { note in
                        PinCardView(itemId: note.id, dropGroupId: itemId)
                            .padding(.leading, 18)
                    }
                }
                .padding(.bottom, 5)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: isGroup ? 10 : 12)
                .fill(isGroup ? theme.cardFill.opacity(0.6) : theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isGroup ? 10 : 12)
                .stroke(isGroup ? theme.secondaryText.opacity(0.18) : theme.cardStroke, lineWidth: isGroup ? 0.8 : 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: isGroup ? 10 : 12))
        .onTapGesture {
            guard !isGroup else { return }
            withAnimation(.easeOut(duration: 0.08)) { tapPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeIn(duration: 0.12)) { tapPulse = false }
            }
            NotificationCenter.default.post(name: .openNoteWindow, object: nil, userInfo: ["id": itemId])
        }
        .contextMenu {
            Button(role: .destructive) { vm.deleteItem(itemId) } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            if !isGroup {
                NotificationCenter.default.post(
                    name: .menuCardHoverChanged, object: nil,
                    userInfo: ["id": itemId, "hovering": hovering]
                )
            }
        }
        .scaleEffect(tapPulse ? 0.97 : (isHovering ? 1.02 : 1))
        .shadow(color: isHovering ? .black.opacity(0.12) : .clear, radius: 6, y: 2)
        .alert("删除便签", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { vm.deleteItem(itemId) }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要删除这个便签吗？此操作不可撤销。")
        }
        .draggable(item?.type == .note ? itemId.uuidString : "")
        .dropDestination(for: String.self) { items, _ in
            guard let idStr = items.first, let id = UUID(uuidString: idStr), id != itemId else { return false }
            vm.moveNote(id, toGroup: isGroup ? itemId : dropGroupId)
            return true
        }
    }

    private func commit() {
        vm.updateTitle(itemId, editingText)
        isEditing = false
    }
}
