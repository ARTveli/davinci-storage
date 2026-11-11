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

    private(set) var itemsByURL: [URL: StorageItem] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        refreshResolveRunning()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshResolveRunning() }
            })
        }
        rescan()
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
        var map: [URL: StorageItem] = [:]
        let rep = r.report
        for it in rep.rows.flatMap(\.items) + rep.deleted.flatMap(\.items) + rep.duplicates.flatMap(\.items) + rep.service {
            map[it.url] = it
        }
        itemsByURL = map
        selected = selected.filter { map[$0] != nil }
        isScanning = false
    }

    // MARK: selection

    var selectedBytes: Int64 { selected.reduce(0) { $0 + (itemsByURL[$1]?.bytes ?? 0) } }

    func isSelected(_ items: [StorageItem]) -> Bool {
        !items.isEmpty && items.allSatisfy { selected.contains($0.url) }
    }

    func setSelected(_ items: [StorageItem], _ on: Bool) {
        for it in items { if on { selected.insert(it.url) } else { selected.remove(it.url) } }
    }

    /// Selects everything that belongs only to projects not modified for `months` months.
    func selectOld() {
        guard let rows = result?.report.rows else { return }
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        let oldIDs = Set(rows.filter { $0.project.lastModified < cutoff }.map(\.id))
        for row in rows where oldIDs.contains(row.id) {
            for it in row.items where Set(it.projectIDs).isSubset(of: oldIDs) && it.match != .byName {
                selected.insert(it.url)
            }
        }
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

    func trashSelected() {
        guard let r = result, !resolveRunning else { return }
        let urls = selected.sorted { $0.path < $1.path }
        lastClean = r.makeCleaner().clean(urls)
        selected = []
        rescan()
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
