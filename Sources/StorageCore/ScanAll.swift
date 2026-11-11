import Foundation

public struct ScanResult: Sendable {
    public let report: Report
    public let locations: Locations
    public let projects: [Project]
    public let libraryRoots: [URL]
}

public let defaultPrefsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Preferences/Blackmagic Design/DaVinci Resolve", isDirectory: true)

/// Full pipeline: Resolve config → projects (read-only) → locations → scan → analyze.
public func scanAll(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                    prefsDir: URL = defaultPrefsDir) -> ScanResult {
    let config = (try? ResolveConfigParser.load(prefsDir: prefsDir)) ?? ResolveConfig(libraries: [], backupRoot: nil)
    var projects: [Project] = []
    var unreadable: [URL] = []
    for lib in config.libraries {
        for db in ProjectReader.findProjectDBs(in: lib) {
            switch ProjectReader.read(dbURL: db, library: lib.name) {
            case .success(let p): projects.append(p)
            case .failure: unreadable.append(db)
            }
        }
    }
    let locations = Locations.real(home: home, config: config)
    let items = scanStorage(locations, projects: projects)
    return ScanResult(report: analyze(projects: projects, unreadable: unreadable, items: items),
                      locations: locations, projects: projects, libraryRoots: config.libraries.map(\.root))
}
