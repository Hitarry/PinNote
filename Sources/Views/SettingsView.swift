import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(PinNoteViewModel.self) private var vm
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showRestoreAlert = false
    @State private var restoreURL: URL?
    @State private var restoreError = false

    var body: some View {
        VStack(spacing: 0) {
            // 自启动：文字在上、开关在下，竖向排列
            VStack(spacing: 4) {
                Text("开机自启动")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .scaleEffect(0.8)
            }
            .padding(.vertical, 1)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

            Divider().padding(.vertical, 5)

            VStack(spacing: 5) {
                actionButton("导出", icon: "arrow.down.doc") { export() }
                actionButton("导入", icon: "arrow.up.doc") { importFile() }
            }

            Spacer()

            Text("PinNote v1.0")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 126, height: 162)
        .alert("恢复数据", isPresented: $showRestoreAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(restoreError ? "文件格式错误，无法恢复" : "导入成功")
        }
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PinNote_export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vm.exportJSON(to: url)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        restoreError = !vm.restoreFromJSON(url: url)
        showRestoreAlert = true
    }
}
