import Foundation

public struct ScanResult: Sendable {
    public let report: Report
    public let locations: Locations
    public let projects: [Project]
    public let libraryRoots: [URL]
    /// Libraries that were reachable (these get backed up before a cleanup).
    public var libraries: [Library] = []
    /// Byte-identical LUTs, with the projects that reference each copy.
    public var luts: [LutGroup] = []
}

public let defaultPrefsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Preferences/Blackmagic Design/DaVinci Resolve", isDirectory: true)

/// Full pipeline: Resolve config → projects (read-only) → locations → scan → analyze.
public func scanAll(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                    prefsDir: URL = defaultPrefsDir) -> ScanResult {
    var warnings: [String] = []
    let config: ResolveConfig
    do {
        config = try ResolveConfigParser.load(prefsDir: prefsDir)
    } catch {
        config = ResolveConfig(libraries: [], backupRoot: nil)
        warnings.append("Не вдалося прочитати налаштування DaVinci (dblist.conf) — список баз невідомий")
    }
    if config.libraries.isEmpty && warnings.isEmpty { warnings.append("У налаштуваннях DaVinci не знайдено жодної бази на диску") }
    for name in config.skippedLibraries { warnings.append("База «\(name)» не на диску (PostgreSQL) — її проєкти не скануються") }
    if !Zstd.isAvailable { warnings.append("Бібліотека zstd недоступна — шляхи Magic Mask у проєктах можуть бути неповними") }

    var projects: [Project] = []
    var unreadable: [URL] = []
    var user = UserGalleries.empty
    for lib in config.libraries {
        guard ProjectReader.isReachable(lib) else {
            warnings.append("База «\(lib.name)» недоступна: \(lib.root.path)")
            continue
        }
        switch ProjectReader.readUserGalleries(in: lib) {
        case .success(let g):
            user.userIDs.formUnion(g.userIDs)
            user.stillIDs.formUnion(g.stillIDs)
        case .failure:
            warnings.append("Не вдалося прочитати галерею користувача (PowerGrades) у базі «\(lib.name)»")
        }
        for db in ProjectReader.findProjectDBs(in: lib) {
            switch ProjectReader.read(dbURL: db, library: lib.name) {
            case .success(let p): projects.append(p)
            case .failure: unreadable.append(db)
            }
        }
    }
    let locations = Locations.real(home: home, config: config)
    let items = scanStorage(locations, projects: projects, user: user)
    var result = ScanResult(report: analyze(projects: projects, unreadable: unreadable, items: items, warnings: warnings),
                            locations: locations, projects: projects, libraryRoots: config.libraries.map(\.root))
    result.libraries = config.libraries.filter(ProjectReader.isReachable)
    if let lutRoot = locations.lutRoot {
        let refs = lutReferences(projects: projects).merging(dctlReferences(root: lutRoot)) { $0.union($1) }
        result.luts = markUsage(findLutDuplicates(root: lutRoot), refs: refs)
    }
    return result
}

public extension ScanResult {
    /// Everything the user can select: report items, old backup snapshots of unprotected projects,
    /// and LUT duplicate copies no project or DCTL uses.
    func selectableItems(keepProjectBackups: Int, protected: Set<String>) -> [StorageItem] {
        let r = report
        return r.rows.flatMap(\.items) + r.deleted.flatMap(\.items) + r.duplicates.flatMap(\.items) + r.service
            + backupTrimItems(r, keep: keepProjectBackups, protected: protected)
            + luts.flatMap(\.copies).filter(\.isSelectable).map(\.storageItem)
    }
}
