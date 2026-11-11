import Foundation

private let projectDBPattern = try! NSRegularExpression(pattern: "^Project\\.db\\.(\\d{14})$")
private let timelinePattern = try! NSRegularExpression(pattern: "^Timeline\\.(\\d{14})$")

/// Old snapshots in one project's backup folder: per series (`Project.db.<stamp>` at the top,
/// `Timeline.<stamp>` in each timeline subfolder) everything except the `keep` newest. Other files are left alone.
public func backupTrimCandidates(in dir: URL, keep: Int) -> [URL] {
    let fm = FileManager.default
    func series(_ folder: URL, _ re: NSRegularExpression) -> [URL] {
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        let stamped: [(URL, String)] = files.compactMap { f in
            let name = f.lastPathComponent
            guard let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let r = Range(m.range(at: 1), in: name) else { return nil }
            return (f, String(name[r]))
        }
        return stamped.sorted { $0.1 > $1.1 }.dropFirst(max(0, keep)).map(\.0)
    }
    var result = series(dir, projectDBPattern)
    let subdirs = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    for sub in subdirs { result += series(sub, timelinePattern) }
    return result.sorted { $0.path < $1.path }
}

/// Old backup snapshots of existing, unprotected projects, as selectable items.
public func backupTrimItems(_ r: Report, keep: Int, protected: Set<String>) -> [StorageItem] {
    var seen = Set<URL>()
    var out: [StorageItem] = []
    for row in r.rows where !protected.contains(row.id) {
        for it in row.items where it.category == .backups && it.match == .uuidFolder
            && it.projectIDs.allSatisfy({ !protected.contains($0) }) {
            for f in backupTrimCandidates(in: it.url, keep: keep) where seen.insert(f).inserted {
                out.append(StorageItem(category: .backups, url: f, bytes: allocatedSize(of: f), projectIDs: it.projectIDs,
                                       match: .uuidFolder, label: "Старий бекап · \(row.project.name)"))
            }
        }
    }
    return out
}
