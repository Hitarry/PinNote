import Foundation
import Observation

@Observable
final class PinNoteViewModel {
    var items: [PinItem] = []
    var collapsedGroupIds: Set<UUID> = []
    var sortStamp = 0

    // 钉住（悬浮窗 / 胶囊）
    var pinnedItemIds: Set<UUID> = [] {
        didSet {
            UserDefaults.standard.set(pinnedItemIds.map(\.uuidString), forKey: "pinnedItemIds")
            for id in oldValue.subtracting(pinnedItemIds) { onPinChanged?(id, false) }
            for id in pinnedItemIds.subtracting(oldValue) { onPinChanged?(id, true) }
        }
    }
    var pillItemIds: Set<UUID> = [] {
        didSet {
            UserDefaults.standard.set(pillItemIds.map(\.uuidString), forKey: "pillItemIds")
            for id in oldValue.subtracting(pillItemIds) { onPillChanged?(id, false) }
            for id in pillItemIds.subtracting(oldValue) { onPillChanged?(id, true) }
        }
    }

    var onPinChanged: ((UUID, Bool) -> Void)?
    var onPillChanged: ((UUID, Bool) -> Void)?

    static let shared = PinNoteViewModel()

    private let saveFile: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dataDir = appSupport.appendingPathComponent("PinNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        saveFile = dataDir.appendingPathComponent("pins.json")

        load()

        if let arr = UserDefaults.standard.stringArray(forKey: "pinnedItemIds") {
            pinnedItemIds = Set(arr.compactMap(UUID.init).filter { findItem($0) != nil })
        }
        if let arr = UserDefaults.standard.stringArray(forKey: "pillItemIds") {
            pillItemIds = Set(arr.compactMap(UUID.init).filter { findItem($0) != nil })
        }
    }

    // MARK: - 列表

    var topLevelItems: [PinItem] {
        items
            .filter { $0.type == .group }
            .sorted { $0.createdAt < $1.createdAt }
        +
        items
            .filter { $0.type == .note }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func sortedGroupNotes(_ group: PinItem) -> [PinItem] {
        group.notes.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - 查找

    func findItem(_ id: UUID) -> PinItem? {
        for item in items {
            if item.id == id { return item }
            if let note = item.notes.first(where: { $0.id == id }) { return note }
        }
        return nil
    }

    private func findIndex(_ id: UUID) -> (groupIndex: Int?, childIndex: Int?) {
        for (i, item) in items.enumerated() {
            if item.id == id { return (nil, i) }
            for (j, note) in item.notes.enumerated() where note.id == id { return (i, j) }
        }
        return (nil, nil)
    }

    // MARK: - CRUD

    func addNote() {
        var copy = items
        copy.append(PinItem(title: "新便签", type: .note))
        items = copy
        save()
    }

    func addGroup() {
        var copy = items
        copy.append(PinItem(title: "新分组", type: .group))
        items = copy
        save()
    }

    func addNote(to groupId: UUID) {
        guard let gi = items.firstIndex(where: { $0.id == groupId && $0.type == .group }) else { return }
        var copy = items
        copy[gi].notes.append(PinItem(title: "新便签", type: .note))
        items = copy
        collapsedGroupIds.remove(groupId)
        save()
    }

    func deleteItem(_ id: UUID) {
        let (gi, ci) = findIndex(id)
        var copy = items
        if let g = gi, let c = ci {
            copy[g].notes.remove(at: c)
        } else if let c = ci {
            copy.remove(at: c)
        }
        items = copy
        pinnedItemIds.remove(id)
        pillItemIds.remove(id)
        save()
    }

    func moveNote(_ id: UUID, toGroup groupId: UUID?) {
        guard let item = findItem(id), item.type == .note else { return }
        var copy = items
        let (gi, ci) = findIndex(id)
        if let g = gi, let c = ci { copy[g].notes.remove(at: c) }
        else if let c = ci { copy.remove(at: c) }
        if let gid = groupId, let gi = copy.firstIndex(where: { $0.id == gid && $0.type == .group }) {
            copy[gi].notes.append(item)
            collapsedGroupIds.remove(gid)
        } else {
            copy.append(item)
        }
        items = copy
        save()
    }

    func updateTitle(_ id: UUID, _ title: String) {
        let (gi, ci) = findIndex(id)
        var copy = items
        if let g = gi, let c = ci { copy[g].notes[c].title = title }
        else if let c = ci { copy[c].title = title }
        items = copy
        save()
    }

    func updateText(_ id: UUID, _ text: String) {
        let (gi, ci) = findIndex(id)
        var copy = items
        if let g = gi, let c = ci { copy[g].notes[c].text = text }
        else if let c = ci { copy[c].text = text }
        items = copy
        save()
    }

    func updateAttributedText(_ id: UUID, _ plain: String, _ data: Data?) {
        let (gi, ci) = findIndex(id)
        var copy = items
        if let g = gi, let c = ci {
            copy[g].notes[c].text = plain
            copy[g].notes[c].attributedData = data
        } else if let c = ci {
            copy[c].text = plain
            copy[c].attributedData = data
        }
        items = copy
        save()
    }

    func setStyle(id: UUID, color: String?, bold: Bool, italic: Bool, fontSize: Double?) {
        let (gi, ci) = findIndex(id)
        var copy = items
        if let g = gi, let c = ci {
            copy[g].notes[c].textColor = color
            copy[g].notes[c].isBold = bold
            copy[g].notes[c].isItalic = italic
            copy[g].notes[c].fontSize = fontSize
        } else if let c = ci {
            copy[c].textColor = color
            copy[c].isBold = bold
            copy[c].isItalic = italic
            copy[c].fontSize = fontSize
        }
        items = copy
        save()
    }

    func toggleCollapseGroup(_ id: UUID) {
        if collapsedGroupIds.contains(id) { collapsedGroupIds.remove(id) }
        else { collapsedGroupIds.insert(id) }
    }

    // MARK: - 钉住 / 胶囊

    func pinItem(_ id: UUID) { pinnedItemIds.insert(id) }
    func unpinItem(_ id: UUID) {
        pinnedItemIds.remove(id)
        pillItemIds.remove(id)
    }
    func enterPillMode(_ id: UUID) {
        pillItemIds.insert(id)
        pinnedItemIds.insert(id)
    }
    func exitPillMode(_ id: UUID) {
        pillItemIds.remove(id)
    }

    // MARK: - 导出 / 导入

    func exportJSON(to url: URL) {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }

    @discardableResult
    func restoreFromJSON(url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PinItem].self, from: data) else { return false }
        items = decoded
        save()
        return true
    }

    // MARK: - 自动备份

    var backupDirectory: URL? {
        get {
            if let path = UserDefaults.standard.string(forKey: "backupDirectory") {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        set { UserDefaults.standard.set(newValue?.path, forKey: "backupDirectory") }
    }

    var isAutoBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "isAutoBackupEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "isAutoBackupEnabled") }
    }

    var backupIntervalMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "backupIntervalMinutes")
            return v > 0 ? v : 10
        }
        set { UserDefaults.standard.set(max(1, newValue), forKey: "backupIntervalMinutes") }
    }

    var backupMaxAgeDays: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "backupMaxAgeDays")
            return v > 0 ? v : 30
        }
        set { UserDefaults.standard.set(max(1, newValue), forKey: "backupMaxAgeDays") }
    }

    private var lastBackupDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastBackupDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastBackupDate") }
    }

    func saveBackup() {
        guard isAutoBackupEnabled, let dir = backupDirectory else { return }
        if let last = lastBackupDate,
           Date().timeIntervalSince(last) < Double(backupIntervalMinutes * 60) { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let url = dir.appendingPathComponent("PinNote_\(formatter.string(from: Date())).json")
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url, options: .atomic)
            lastBackupDate = Date()
            cleanOldBackups(in: dir)
        }
    }

    private func cleanOldBackups(in dir: URL) {
        let cutoff = Date().addingTimeInterval(-Double(backupMaxAgeDays * 86400))
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for file in files where file.lastPathComponent.hasPrefix("PinNote_") && file.pathExtension == "json" {
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate, created < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func listBackupFiles() -> [(url: URL, date: Date)] {
        guard let dir = backupDirectory else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        return files
            .filter { $0.lastPathComponent.hasPrefix("PinNote_") && $0.pathExtension == "json" }
            .compactMap { url in
                guard let attrs = try? url.resourceValues(forKeys: [.creationDateKey]),
                      let date = attrs.creationDate else { return nil }
                return (url, date)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 持久化

    private func save() {
        sortStamp += 1
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: saveFile, options: .atomic)
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.saveBackup()
            }
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: saveFile),
           let decoded = try? JSONDecoder().decode([PinItem].self, from: data) {
            items = decoded
        }
    }
}
