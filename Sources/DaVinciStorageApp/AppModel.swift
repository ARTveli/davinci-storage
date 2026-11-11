import AppKit
import Foundation
import StorageCore

@MainActor
final class AppModel: ObservableObject {
    static let resolveBundleID = "com.blackmagic-design.DaVinciResolve"

    @Published private(set) var result: ScanResult?
    @Published private(set) var isScanning = false
    @Published var selected: Set<URL> = []
    @Published var months = 3
    @Published private(set) var resolveRunning = false
    @Published var lastClean: CleanResult?
    /// Outcome of the library backup made before the last cleanup (folder name or error text).
    @Published var lastBackupNote: String?
    @Published var settings = StorageSettings.load() {
        didSet { settings.save(); if oldValue.keepProjectBackups != settings.keepProjectBackups
                    || oldValue.protectedProjectIDs != settings.protectedProjectIDs { rebuildItems() } }
    }
    /// Old snapshots of unprotected projects' backups (per settings.keepProjectBackups).
    @Published private(set) var trimItems: [StorageItem] = []

    // UI state (kept here instead of @State — see Box.swift).
    @Published var section: SidebarSection? = .projects
    @Published var search = ""
    @Published var focusedProject: String? {
        didSet { if focusedProject != nil && focusedProject != oldValue { inspectorShown = true } }
    }
    @Published var inspectorShown = false
    @Published var confirming = false

    private(set) var itemsByURL: [URL: StorageItem] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        refreshResolveRunning()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resolveStateChanged() }
            })
        }
        rescan()
    }

    /// After a Resolve session the old scan (and anything selected from it) may be stale.
    private func resolveStateChanged() {
        let wasRunning = resolveRunning
        refreshResolveRunning()
        if wasRunning && !resolveRunning {
            selected = []
            rescan()
        }
    }

    func refreshResolveRunning() {
        resolveRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.resolveBundleID }
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let r = scanAll()
            await MainActor.run { self.apply(r) }
        }
    }

    private func apply(_ r: ScanResult) {
        result = r
        rebuildItems()
        isScanning = false
    }

    private func rebuildItems() {
        guard let r = result else { return }
        trimItems = backupTrimItems(r.report, keep: settings.keepProjectBackups, protected: settings.protectedProjectIDs)
        var map: [URL: StorageItem] = [:]
        for it in r.selectableItems(keepProjectBackups: settings.keepProjectBackups, protected: settings.protectedProjectIDs) {
            map[it.url] = it
        }
        itemsByURL = map
        selected = selected.filter { map[$0] != nil }
    }

    // MARK: protected projects

    func isProtected(_ id: String) -> Bool { settings.protectedProjectIDs.contains(id) }

    func setProtected(_ id: String, _ on: Bool) {
        if on { settings.protectedProjectIDs.insert(id) } else { settings.protectedProjectIDs.remove(id) }
    }

    func selectOldBackups() { selected.formUnion(trimItems.map(\.url)) }

    func trimItems(for projectID: String) -> [StorageItem] { trimItems.filter { $0.projectIDs.contains(projectID) } }

    // MARK: selection

    var selectedBytes: Int64 { selected.reduce(0) { $0 + (itemsByURL[$1]?.bytes ?? 0) } }

    func isSelected(_ items: [StorageItem]) -> Bool {
        !items.isEmpty && items.allSatisfy { selected.contains($0.url) }
    }

    func setSelected(_ items: [StorageItem], _ on: Bool) {
        for it in items { if on { selected.insert(it.url) } else { selected.remove(it.url) } }
    }

    /// Selects everything that belongs only to projects not modified for `months` months (see `oldSelection`).
    func selectOld(months: Int) {
        guard let r = result?.report else { return }
        self.months = months
        selected.formUnion(oldSelection(r, months: months, protected: settings.protectedProjectIDs))
    }

    var selectedCount: Int { selected.count }

    /// Unique on-disk total per sidebar section.
    func total(_ s: SidebarSection) -> Int64 {
        guard let r = result?.report else { return 0 }
        let items: [StorageItem]
        switch s {
        case .projects: items = r.rows.flatMap(\.items)
        case .leftovers: items = (r.deleted + r.duplicates).flatMap(\.items)
        case .service: items = r.service
        case .luts: return result?.luts.reduce(0) { $0 + $1.wasted } ?? 0
        }
        var seen = Set<URL>()
        return items.reduce(0) { seen.insert($1.url).inserted ? $0 + $1.bytes : $0 }
    }

    var isUncertain: Bool { result?.report.isUncertain ?? true }

    /// Items from leftover groups whose "deleted" status could not be proven.
    var uncertainURLs: Set<URL> {
        guard let r = result?.report else { return [] }
        return Set((r.deleted + r.duplicates).filter(\.uncertain).flatMap(\.items).map(\.url))
    }

    func isOld(_ p: Project) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        return p.lastModified < cutoff
    }

    /// Names of other projects that also use this item.
    func sharedWith(_ it: StorageItem) -> [String] {
        guard it.projectIDs.count > 1, let rows = result?.report.rows else { return [] }
        return rows.filter { it.projectIDs.contains($0.id) }.map(\.project.name)
    }

    /// Re-scans, backs up every library (and rotates old backups), then trashes only selected items that still
    /// exist with the same owners as when chosen. If the backup fails, nothing is trashed.
    func trashSelected() {
        guard result != nil, !resolveRunning, !isScanning else { return }
        let chosen = selected.compactMap { itemsByURL[$0] }
        let s = settings
        selected = []
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let fresh = scanAll()
            var freshItems: [URL: StorageItem] = [:]
            for it in fresh.selectableItems(keepProjectBackups: s.keepProjectBackups, protected: s.protectedProjectIDs) {
                freshItems[it.url] = it
            }
            var ok: [URL] = []
            var stale: [(url: URL, reason: String)] = []
            for it in chosen {
                if let now = freshItems[it.url], Set(now.projectIDs) == Set(it.projectIDs) { ok.append(it.url) }
                else { stale.append((it.url, "змінилося після сканування — переглянь і вибери знову")) }
            }

            var note: String
            var res = CleanResult()
            do {
                let folder = try LibraryBackup.create(libraries: fresh.libraries, in: s.backupFolder, date: Date(),
                                                      version: LibraryBackup.resolveVersion())
                let rotated = LibraryBackup.rotate(in: s.backupFolder, keep: s.keepLibraryBackups)
                note = "Бекап баз: \(folder.lastPathComponent)"
                    + (rotated.isEmpty ? "" : " · старих бекапів у Кошик: \(rotated.count)")
                res = fresh.makeCleaner().clean(ok.sorted { $0.path < $1.path })
            } catch {
                note = "Очищення скасовано — бекап баз не вдався. "
                    + ((error as? LibraryBackup.BackupError)?.message ?? error.localizedDescription)
                res.failed = ok.map { ($0, "не видалено: бекап баз не вдався") }
            }
            res.failed += stale
            let finalNote = note
            let finalRes = res
            await MainActor.run {
                self.isScanning = false
                self.lastBackupNote = finalNote
                self.lastClean = finalRes
                self.rescan()
            }
        }
    }
}

extension MatchKind {
    var explanation: String {
        switch self {
        case .uuidFolder: "за ID проєкту"
        case .dbPath: "шлях записаний у проєкті"
        case .stillID: "за ID стілу"
        case .byName: "за назвою папки — неточно"
        case .unlinked: "не прив'язано"
        }
    }
}
