import SwiftUI

struct MenuBarView: View {
    @Environment(PinNoteViewModel.self) private var vm
    @State private var showSettings = false
    @State private var showHelp = false

    var body: some View {
        let _ = vm.sortStamp
        let theme = ThemeConfig.light

        VStack(spacing: 0) {
            // 顶栏：虚线框内新建按钮 + 右侧帮助/设置
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    dashButton("新建便签", icon: "plus", theme: theme) { vm.addNote() }
                    dashButton("新建分组", icon: "folder.badge.plus", theme: theme) { vm.addGroup() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .fill(theme.secondaryText.opacity(0.15))
                )

                Spacer()

                HStack(spacing: 6) {
                    Button(action: toggleHelp) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13))
                            .foregroundColor(theme.secondaryText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showHelp, arrowEdge: .top) { helpContent }

                    Button(action: toggleSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(theme.secondaryText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSettings, arrowEdge: .top) {
                        SettingsView()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .fill(theme.secondaryText.opacity(0.12))
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 8) {
                    if vm.topLevelItems.isEmpty {
                        Text("点击上方按钮新建便签或分组")
                            .font(.system(size: 11))
                            .foregroundColor(theme.secondaryText.opacity(0.3))
                            .padding(.top, 24)
                    } else {
                        ForEach(vm.topLevelItems) { item in
                            PinCardView(itemId: item.id)
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let idStr = items.first, let id = UUID(uuidString: idStr) else { return false }
                vm.moveNote(id, toGroup: nil)
                return true
            }
        }
        .frame(width: 300, height: 486)
        .background {
            Color.clear.background(.ultraThinMaterial)
        }
        .background {
            Button("") { vm.addNote() }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
        .background {
            Button("") { vm.addGroup() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0)
        }
        .background {
            Button("") { NotificationCenter.default.post(name: .closePopoverShortcut, object: nil) }
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
        .background {
            Button("") { toggleSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
        .background {
            Button("") { toggleHelp() }
                .keyboardShortcut("/", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
    }

    private func dashButton(_ label: String, icon: String, theme: ThemeConfig, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
                Text(label).font(.system(size: 11))
            }
            .foregroundColor(theme.secondaryText.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accentColor)
                Text("帮助").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .padding(.bottom, 6)
            Divider()
            Text("快捷键").font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary).padding(.top, 5).padding(.bottom, 2)
            shortcutRow("⌘N", "新建便签")
            shortcutRow("⇧⌘N", "新建分组")
            shortcutRow("⌘W", "关闭弹窗")
            shortcutRow("⌘,", "设置")
            shortcutRow("⌘/", "帮助")
            Divider().padding(.top, 4)
            Text("操作").font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary).padding(.top, 5).padding(.bottom, 2)
            tipRow("点击便签卡片 → 弹出悬浮窗")
            tipRow("悬浮窗右上角 → 样式 / 钉住 / 胶囊")
            tipRow("胶囊吸附屏幕边缘，悬停预览")
            tipRow("右键菜单栏图标 → 退出")
        }
        .padding(12)
        .frame(width: 200)
    }

    private func shortcutRow(_ keys: String, _ desc: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 46, alignment: .leading)
            Text(desc).font(.system(size: 10))
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private func tipRow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "lightbulb").font(.system(size: 8)).foregroundColor(.accentColor)
            Text(text).font(.system(size: 9))
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private func toggleSettings() {
        if showSettings { showSettings = false }
        else { showHelp = false; showSettings = true }
    }

    private func toggleHelp() {
        if showHelp { showHelp = false }
        else { showSettings = false; showHelp = true }
    }
}
