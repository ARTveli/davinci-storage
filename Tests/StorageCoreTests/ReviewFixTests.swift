import Foundation
import SQLite3
import Testing
@testable import StorageCore

/// Regression tests for the findings of the final review (2026-11-11).
@Suite struct ReviewFixTests {
    // MARK: Critical 1 — user-level galleries (PowerGrades) are not deleted projects

    @Test func userGalleryReadFromUserDB() throws {
        let root = makeTempDir()
        try makeUserDB(at: root.appendingPathComponent("Resolve Projects/Users/guest/User.db"),
                       userID: "BF5DCC6F-F4F9-481D-8348-BE298255D81A", stillIDs: ["AAAAAAAA-0000-0000-0000-000000000001"])
        let g = try ProjectReader.readUserGalleries(in: Library(name: "L", root: root)).get()
        #expect(g.userIDs == ["bf5dcc6f-f4f9-481d-8348-be298255d81a"])
        #expect(g.stillIDs == ["aaaaaaaa-0000-0000-0000-000000000001"])
    }

    @Test func userGalleryFolderNotListed() {
        let root = makeTempDir(), loc = testLocations(root)
        let user = "bf5dcc6f-f4f9-481d-8348-be298255d81a"
        makeFile(loc.galleryProjectRoot.appendingPathComponent("\(user)/Info.txt"))
        let items = scanStorage(loc, projects: [], user: UserGalleries(userIDs: [user], stillIDs: []))
        #expect(items.isEmpty)
    }

    @Test func galleryWithoutProjectNameNotListed() throws {
        let root = makeTempDir(), loc = testLocations(root)
        let dir = loc.galleryProjectRoot.appendingPathComponent("f52f586d-9380-4c7e-a049-adcbece6c570")
        makeFile(dir.appendingPathComponent("x.dpx"))
        try "Database Name: ARTveli_COLOR_COURSE\nUser Name: guest\n".write(to: dir.appendingPathComponent("Info.txt"), atomically: true, encoding: .utf8)
        #expect(scanStorage(loc, projects: []).isEmpty)
    }

    @Test func legacyStillOwnedByUserNotListed() {
        let root = makeTempDir(), loc = testLocations(root)
        let still = "aaaaaaaa-0000-0000-0000-000000000001"
        makeFile(loc.galleryLegacyRoot.appendingPathComponent("\(still).dpx"))
        #expect(scanStorage(loc, projects: [], user: UserGalleries(userIDs: [], stillIDs: [still])).isEmpty)
    }

    // MARK: Critical 2 — failures must make "deleted" uncertain

    @Test func missingDblistIsWarning() throws {
        let home = makeTempDir()
        let prefs = home.appendingPathComponent("Prefs")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        makeFile(home.appendingPathComponent("Movies/CacheClip/585bbd4a-ba19-4d98-b863-18e2f5f4b8c0/a.bin"))
        let r = scanAll(home: home, prefsDir: prefs).report
        #expect(!r.warnings.isEmpty)
        #expect(r.deleted.allSatisfy { $0.uncertain })
        #expect(r.isUncertain)
    }

    @Test func unreachableLibraryIsWarning() throws {
        let home = makeTempDir()
        let prefs = home.appendingPathComponent("Prefs")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try "gone:/Volumes/NOPE_\(UUID().uuidString):*:::DISK\n".write(to: prefs.appendingPathComponent("dblist.conf"), atomically: true, encoding: .utf8)
        #expect(scanAll(home: home, prefsDir: prefs).report.isUncertain)
    }

    @Test func nonDiskLibrariesReported() {
        #expect(ResolveConfigParser.parseSkippedLibraries("a:/x:*:::DISK\nPG:host:5432:::PG\n") == ["PG"])
    }

    @Test func stepErrorFailsProjectRead() throws {
        let db = makeTempDir().appendingPathComponent("Project.db")
        try makeProjectDB(at: db, id: "a", name: "A", lastMod: 1)
        // Replace the clip table with a view that errors while stepping (integer overflow).
        var h: OpaquePointer?
        sqlite3_open(db.path, &h)
        sqlite3_exec(h, "DROP TABLE BtVideoInfo; CREATE VIEW BtVideoInfo AS SELECT abs(-9223372036854775808) AS Clip", nil, nil, nil)
        sqlite3_close(h)
        guard case .failure = ProjectReader.read(dbURL: db, library: "L") else {
            Issue.record("a partial read must fail"); return
        }
    }

    // MARK: Critical 3 — Magic Mask paths inside zstd-compressed blobs

    @Test func extractsMaskFromZstdCompressedBlob() throws {
        let path = "/Users/artveli/MAGIC_MASK_2_DAVINCI/GOR_ACBA_AMUNDI/Magic Mask"
        var payload = Array("\n7".utf8) + Array(path.utf8) + [0x12, 0x1B] + Array("shot_01.mov".utf8)
        payload += Array(String(repeating: "abcabcabd", count: 400).utf8) + Array(path.utf8)
        guard let compressed = zstdCLI(payload) else { return } // zstd CLI not installed → nothing to test
        let blob: [UInt8] = [0, 0, 0, 2, 0, 0, 0, 0xC8, 0x81] + compressed
        #expect(!blob.containsSubsequence(Array(path.utf8)), "fixture must not expose the path raw")
        #expect(ProjectReader.extractMagicMaskDirs(from: blob) == [path])
    }

    @Test func regexDoesNotSpanEarlierPath() {
        let blob = Array("/Users/a/other.mov-/Users/x/MM/A/Magic Mask".utf8)
        #expect(ProjectReader.extractMagicMaskDirs(from: blob) == ["/Users/x/MM/A/Magic Mask"])
    }

    // MARK: Important 4 / 10 — uncertainty propagates and is explained

    @Test func duplicatesUncertainWhenUnreadable() {
        let root = makeTempDir()
        let original = root.appendingPathComponent("A/Magic Mask")
        let copy = root.appendingPathComponent("B")
        makeFile(original.appendingPathComponent("s.mov"))
        makeFile(copy.appendingPathComponent("Magic Mask/s.mov"))
        let r = analyze(projects: [project("a", "A")], unreadable: [URL(fileURLWithPath: "/x/Project.db")], items: [
            StorageItem(category: .magicMask, url: original, bytes: 1, projectIDs: ["a"], match: .dbPath, label: "A"),
            StorageItem(category: .magicMask, url: copy, bytes: 1, projectIDs: [], match: .unlinked, label: "B"),
        ])
        #expect(r.duplicates.first?.uncertain == true)
    }

    @Test func uncertainReasonSaysSo() {
        let r = analyze(projects: [], unreadable: [], items: [item(.cache, "/c/z", 1, ["z"])], warnings: ["x"])
        #expect(r.deleted.first?.uncertain == true)
        #expect(r.deleted.first?.reason.contains("не вдалося") == true)
    }

    // MARK: Important 5 — claims match case-insensitively

    @Test func claimMatchIsCaseInsensitive() {
        let root = makeTempDir(), loc = testLocations(root)
        makeFile(loc.magicMaskRoots[0].appendingPathComponent("ukravit/Magic Mask/s.mov"))
        let dbSpelling = loc.magicMaskRoots[0].appendingPathComponent("UKRAVIT/Magic Mask")
        let masks = scanStorage(loc, projects: [project("u", "UKRAVIT", masks: [dbSpelling])]).filter { $0.category == .magicMask }
        #expect(masks.count == 1)
        #expect(masks.first?.match == .dbPath)
    }

    // MARK: Important 6 — only the Magic Mask part of a mixed folder

    @Test func unlinkedMixedFolderTargetsMagicMaskOnly() {
        let root = makeTempDir(), loc = testLocations(root)
        let x = loc.magicMaskRoots[0].appendingPathComponent("PROM_709")
        makeFile(x.appendingPathComponent("Magic Mask/s.mov"))
        makeFile(x.appendingPathComponent("render.mov"))
        let item = scanStorage(loc, projects: []).first { $0.category == .magicMask }
        #expect(item.map(normalizedPath) == normalizedPath(x.appendingPathComponent("Magic Mask")))
    }

    // MARK: Important 7 — legacy still shared by two projects

    @Test func legacyStillKeepsAllOwners() {
        let root = makeTempDir(), loc = testLocations(root)
        let still = "02259a23-ff34-41b7-b8e6-2ce9f970cccb"
        makeFile(loc.galleryLegacyRoot.appendingPathComponent("\(still).dpx"))
        let items = scanStorage(loc, projects: [project("a", "A", stills: [still]), project("b", "B", stills: [still])])
        #expect(Set(items.first?.projectIDs ?? []) == ["a", "b"])
    }

    // MARK: Important 9 — auto-selection of old projects

    @Test func nullLastModFallsBackToFileDate() throws {
        let db = makeTempDir().appendingPathComponent("Project.db")
        try makeProjectDB(at: db, id: "a", name: "A", lastMod: 1)
        var h: OpaquePointer?
        sqlite3_open(db.path, &h)
        sqlite3_exec(h, "UPDATE SM_Project SET LastModTimeInSecs = NULL", nil, nil, nil)
        sqlite3_close(h)
        let p = try ProjectReader.read(dbURL: db, library: "L").get()
        #expect(p.lastModified > Date(timeIntervalSince1970: 1_000_000_000))
    }

    @Test func oldSelectionSkipsSharedByNameAndRecentDuplicates() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        func p(_ id: String, _ lib: String, _ d: Date) -> Project {
            Project(id: id, name: id, library: lib, dbURL: URL(fileURLWithPath: "/\(lib)/\(id)"), lastModified: d, stillIDs: [], magicMaskDirs: [])
        }
        let items = [
            item(.cache, "/c/a", 1, ["a"]),                              // old only → selected
            item(.magicMask, "/mm/shared", 1, ["a", "b"], .dbPath),       // shared with recent b → no
            item(.magicMask, "/mm/byname", 1, ["a"], .byName),            // by name → no
            item(.cache, "/c/t", 1, ["t"]),                               // t old in L1, recent in L2 → no
        ]
        let r = analyze(projects: [p("a", "L1", old), p("b", "L1", now), p("t", "L1", old), p("t", "L2", now)], unreadable: [], items: items)
        #expect(oldSelection(r, months: 3, now: now).map(\.path) == ["/c/a"])
    }

    @Test func noOldSelectionWhenUncertain() {
        let r = analyze(projects: [project("a", "A")], unreadable: [URL(fileURLWithPath: "/x")], items: [item(.cache, "/c/a", 1, ["a"])])
        #expect(oldSelection(r, months: 3, now: Date()).isEmpty)
    }
}

// MARK: helpers

func makeUserDB(at url: URL, userID: String, stillIDs: [String]) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw NSError(domain: "fixture", code: 2) }
    defer { sqlite3_close(db) }
    sqlite3_exec(db, "CREATE TABLE SM_User (SM_User_id uuid); INSERT INTO SM_User VALUES ('\(userID)')", nil, nil, nil)
    sqlite3_exec(db, "CREATE TABLE \"Gallery::GyStill\" (\"Gallery::GyStill_id\" uuid)", nil, nil, nil)
    for s in stillIDs { sqlite3_exec(db, "INSERT INTO \"Gallery::GyStill\" VALUES ('\(s)')", nil, nil, nil) }
}

/// Compresses with the zstd command-line tool (Homebrew); nil when it isn't installed.
func zstdCLI(_ data: [UInt8]) -> [UInt8]? {
    guard let tool = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd"].first(where: FileManager.default.isExecutableFile) else { return nil }
    let dir = makeTempDir()
    let input = dir.appendingPathComponent("in.bin")
    FileManager.default.createFile(atPath: input.path, contents: Data(data))
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = ["-q", "-19", "-f", input.path, "-o", dir.appendingPathComponent("out.zst").path]
    try? p.run()
    p.waitUntilExit()
    return (try? Data(contentsOf: dir.appendingPathComponent("out.zst"))).map { Array($0) }
}

extension Array where Element == UInt8 {
    func containsSubsequence(_ s: [UInt8]) -> Bool {
        guard !s.isEmpty, s.count <= count else { return false }
        return (0...(count - s.count)).contains { Array(self[$0..<($0 + s.count)]) == s }
    }
}

extension Optional where Wrapped == StorageItem {
    func map(_ f: (URL) -> String) -> String? { self.map { f($0.url) } }
}
