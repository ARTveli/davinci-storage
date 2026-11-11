import Foundation

public struct ProjectRow: Identifiable, Sendable {
    public let id: String
    public let project: Project
    public let items: [StorageItem]
    public let bytes: [Category: Int64]
    public let total: Int64
}

public struct LeftoverGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let reason: String
    public let items: [StorageItem]
    public let total: Int64
    public let uncertain: Bool
}

public struct Report: Sendable {
    public let rows: [ProjectRow]
    public let deleted: [LeftoverGroup]
    public let duplicates: [LeftoverGroup]
    public let service: [StorageItem]
    public let unreadable: [URL]
    /// Scan-level problems (config unreadable, library unreachable, zstd missing…).
    public let warnings: [String]
    public let grandTotal: Int64

    /// True when the scan can't prove that leftovers really belong to no project.
    public var isUncertain: Bool { !unreadable.isEmpty || !warnings.isEmpty }
}

public func analyze(projects: [Project], unreadable: [URL], items: [StorageItem], warnings: [String] = []) -> Report {
    let uncertain = !unreadable.isEmpty || !warnings.isEmpty
    let caveat = " — але частину даних не вдалося прочитати, перевір вручну"
    let known = Set(projects.map(\.id))
    var service: [StorageItem] = []
    var orphans: [StorageItem] = []
    var perProject: [String: [StorageItem]] = [:]

    for it in items {
        if it.category == .service { service.append(it); continue }
        let owners = it.projectIDs.filter(known.contains)
        if owners.isEmpty { orphans.append(it) } else { for o in owners { perProject[o, default: []].append(it) } }
    }

    let rows = projects.map { p -> ProjectRow in
        let its = perProject[p.id] ?? []
        var bytes: [Category: Int64] = [:]
        for it in its { bytes[it.category, default: 0] += it.bytes }
        return ProjectRow(id: p.id, project: p, items: its, bytes: bytes, total: its.reduce(0) { $0 + $1.bytes })
    }.sorted { ($0.total, $0.project.name) > ($1.total, $1.project.name) }

    // Duplicates: an unlinked Magic Mask folder whose files are (≥90 %) the same as a referenced one.
    let referenced = items.filter { $0.category == .magicMask && $0.match == .dbPath }
    let refSignatures = referenced.map { ($0, fileSignatures($0.url)) }
    var duplicates: [LeftoverGroup] = []
    var remaining: [StorageItem] = []
    for it in orphans {
        if it.category == .magicMask, it.match == .unlinked {
            let sig = fileSignatures(it.url)
            if !sig.isEmpty, let (orig, _) = refSignatures.first(where: { Double($0.1.intersection(sig).count) >= 0.9 * Double(sig.count) }) {
                duplicates.append(LeftoverGroup(id: "dup:" + it.url.path, title: "Копія: \(it.label)",
                                                reason: "ті самі файли, що й у \(orig.url.path)" + (uncertain ? caveat : ""),
                                                items: [it], total: it.bytes, uncertain: uncertain))
                continue
            }
        }
        remaining.append(it)
    }

    // Deleted: group by unknown project UUID, otherwise by category + label.
    var order: [String] = []
    var groups: [String: [StorageItem]] = [:]
    for it in remaining {
        let key: String
        if let id = it.projectIDs.first { key = "id:" + id }
        else if it.category == .stills { key = "stills-unlinked" }
        else { key = "\(it.category.rawValue):\(it.label)" }
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(it)
    }
    let deleted = order.map { key -> LeftoverGroup in
        let its = groups[key]!
        let title: String
        let reason: String
        if key.hasPrefix("id:") {
            title = its.first { UUID(uuidString: $0.label) == nil }?.label ?? its[0].label
            reason = "проєкту з таким ID немає в жодній базі"
        } else if key == "stills-unlinked" {
            title = "Стіли без проєкту"
            reason = "ці стіли не належать жодному проєкту"
        } else {
            title = its[0].label
            reason = "жоден проєкт не посилається на цю папку"
        }
        return LeftoverGroup(id: key, title: title, reason: reason + (uncertain ? caveat : ""), items: its,
                             total: its.reduce(0) { $0 + $1.bytes }, uncertain: uncertain)
    }.sorted { $0.total > $1.total }

    var seen = Set<String>()
    var grand: Int64 = 0
    for it in items where seen.insert(normalizedPath(it.url)).inserted { grand += it.bytes }

    return Report(rows: rows, deleted: deleted, duplicates: duplicates.sorted { $0.total > $1.total },
                  service: service, unreadable: unreadable, warnings: warnings, grandTotal: grand)
}

/// Items to pre-select for "older than N months": only items whose every owner is old (in every library
/// it appears in), never folder-name matches, and nothing at all when the scan is uncertain.
public func oldSelection(_ r: Report, months: Int, now: Date = Date(), protected: Set<String> = []) -> [URL] {
    guard !r.isUncertain else { return [] }
    let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: now) ?? now
    var newestByID: [String: Date] = [:]
    for row in r.rows { newestByID[row.id] = max(newestByID[row.id] ?? .distantPast, row.project.lastModified) }
    let oldIDs = Set(newestByID.filter { $0.value < cutoff }.keys).subtracting(protected)
    var urls = Set<URL>()
    for row in r.rows where oldIDs.contains(row.id) {
        for it in row.items where it.match != .byName && Set(it.projectIDs).isSubset(of: oldIDs) {
            urls.insert(it.url)
        }
    }
    return urls.sorted { $0.path < $1.path }
}

/// "filename|size" for every file under `url` — enough to recognise a copied Magic Mask folder.
private func fileSignatures(_ url: URL) -> Set<String> {
    guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return [] }
    var result = Set<String>()
    for case let f as URL in walker {
        guard let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true,
              f.lastPathComponent != ".DS_Store" else { continue }
        result.insert("\(f.lastPathComponent.precomposedStringWithCanonicalMapping)|\(v.fileSize ?? 0)")
    }
    return result
}
