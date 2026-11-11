import Foundation
import Testing
@testable import StorageCore

@Suite struct ScanAllTests {
    @Test func endToEndOnFakeHome() throws {
        let home = makeTempDir()
        let prefs = home.appendingPathComponent("Prefs")
        let lib = home.appendingPathComponent("DB")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try "main:\(lib.path):*:::DISK\n".write(to: prefs.appendingPathComponent("dblist.conf"), atomically: true, encoding: .utf8)
        let id = "585bbd4a-ba19-4d98-b863-18e2f5f4b8c0"
        try makeProjectDB(at: lib.appendingPathComponent("Resolve Projects/Users/guest/Projects/AD/UKRAVIT/Project.db"),
                          id: id, name: "UKRAVIT", lastMod: 1794331426)
        // A broken project database next to it.
        makeFile(lib.appendingPathComponent("Resolve Projects/Users/guest/Projects/BROKEN/Project.db"), bytes: 100)
        makeFile(home.appendingPathComponent("Movies/CacheClip/\(id)/a.bin"))

        let result = scanAll(home: home, prefsDir: prefs)
        #expect(result.report.rows.map(\.project.name) == ["UKRAVIT"])
        #expect(result.report.rows[0].bytes[.cache] ?? 0 > 0)
        #expect(result.report.unreadable.map(\.lastPathComponent) == ["Project.db"])
        #expect(result.libraryRoots.map(normalizedPath) == [normalizedPath(lib)])
    }
}
