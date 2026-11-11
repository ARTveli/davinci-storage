import Foundation
import SQLite3
import Testing
@testable import StorageCore

/// Regression tests for the v2 review findings (2026-11-11).
@Suite struct V2ReviewFixTests {
    func write(_ url: URL, _ text: String) {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! text.write(to: url, atomically: true, encoding: .utf8)
    }

    // I1 — PowerGrade (User.db) LUT usage
    @Test func lutUsedByPowerGradeIsFound() throws {
        let userDB = makeTempDir().appendingPathComponent("User.db")
        var h: OpaquePointer?
        sqlite3_open(userDB.path, &h)
        sqlite3_exec(h, "CREATE TABLE \"ListMgt::LmVersion\" (Data blob); INSERT INTO \"ListMgt::LmVersion\" VALUES (X'0A1D' || CAST('3_LogC3_LUT/Pack/Grade.cube' AS BLOB))", nil, nil, nil)
        sqlite3_close(h)
        let scan = lutReferences(databases: [(userDB, "PowerGrade · 2026_new")])
        #expect(scan.complete)
        #expect(scan.refs.contains { $0.key.hasSuffix("grade.cube") && $0.value.contains("PowerGrade · 2026_new") })
    }

    // I2 — fail closed
    @Test func unreadableDatabaseMakesScanIncomplete() {
        let bogus = makeFile(makeTempDir().appendingPathComponent("Project.db"), bytes: 100)   // not SQLite
        #expect(lutReferences(databases: [(bogus, "X")]).complete == false)
    }

    @Test func incompleteUsageLocksEveryCopy() {
        let root = makeTempDir()
        write(root.appendingPathComponent("A/x.cube"), "same")
        write(root.appendingPathComponent("B/y.cube"), "same")
        let g = lockAll(findLutDuplicates(root: root), reason: "невідомо")
        #expect(g[0].copies.allSatisfy { !$0.isSelectable })
    }

    // I3 — one copy always survives, enforced in core; Cleaner only allows selectable copies
    @Test func survivorKeptWhenWholeGroupSelected() {
        let a = LutCopy(url: URL(fileURLWithPath: "/L/a.cube"), relativePath: "a.cube", bytes: 1)
        let b = LutCopy(url: URL(fileURLWithPath: "/L/b.cube"), relativePath: "b.cube", bytes: 1)
        let (kept, spared) = sparingOneCopyPerGroup([a.url, b.url, URL(fileURLWithPath: "/x")], groups: [LutGroup(id: "h", copies: [a, b])])
        #expect(spared.count == 1)
        #expect(kept.count == 2)
        #expect(kept.contains(URL(fileURLWithPath: "/x")))
    }

    @Test func cleanerRefusesUsedLutAndDctl() {
        let root = makeTempDir()
        let lutRoot = root.appendingPathComponent("LUT")
        let free = makeFile(lutRoot.appendingPathComponent("A/x.cube"))
        let used = makeFile(lutRoot.appendingPathComponent("B/x.cube"))
        let dctl = makeFile(lutRoot.appendingPathComponent("DCTL/look.dctl"))
        var loc = testLocations(root)
        loc.lutRoot = lutRoot
        var usedCopy = LutCopy(url: used, relativePath: "B/x.cube", bytes: 1)
        usedCopy.usedBy = ["P"]
        var r = ScanResult(report: analyze(projects: [], unreadable: [], items: []), locations: loc, projects: [], libraryRoots: [])
        r.luts = [LutGroup(id: "h", copies: [LutCopy(url: free, relativePath: "A/x.cube", bytes: 1), usedCopy])]
        let c = r.makeCleaner()
        #expect(c.validate(free) == nil)
        #expect(c.validate(used) != nil)
        #expect(c.validate(dctl) != nil)
    }

    // I4 — rotation never trashes a backup connected as a live library; create skips libraries inside the backup root
    @Test func rotationSkipsBackupUsedAsLibrary() throws {
        let tmp = makeTempDir(), root = tmp.appendingPathComponent("B")
        let lib = makeLibrary(tmp.appendingPathComponent("DB"), name: "L", files: ["x/Project.db": 10])
        let old = try LibraryBackup.create(libraries: [lib], in: root, date: Date(timeIntervalSince1970: 1), version: "1")
        _ = try LibraryBackup.create(libraries: [lib], in: root, date: Date(timeIntervalSince1970: 2), version: "1")
        let connected = Library(name: "restored", root: old.appendingPathComponent("L"))
        var trashed: [URL] = []
        LibraryBackup.rotate(in: root, keep: 1, liveLibraries: [connected], trash: { trashed.append($0) })
        #expect(trashed.isEmpty)
    }

    @Test func createSkipsLibrariesInsideBackupRoot() throws {
        let tmp = makeTempDir(), root = tmp.appendingPathComponent("B")
        let lib = makeLibrary(tmp.appendingPathComponent("DB"), name: "L", files: ["x/Project.db": 10])
        let restored = makeLibrary(root.appendingPathComponent("old/L"), name: "restored", files: ["y/Project.db": 10])
        let out = try LibraryBackup.create(libraries: [lib, restored], in: root, date: Date(), version: "1")
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).filter { !$0.hasPrefix(".") } == ["L"])
    }

    // I5 — protecting a project deselects its items
    @Test func protectingDeselectsOwnedItems() {
        let items: [URL: StorageItem] = [
            URL(fileURLWithPath: "/c/a"): item(.cache, "/c/a", 1, ["a"]),
            URL(fileURLWithPath: "/mm/ab"): item(.magicMask, "/mm/ab", 1, ["a", "b"], .dbPath),
            URL(fileURLWithPath: "/c/b"): item(.cache, "/c/b", 1, ["b"]),
        ]
        let left = deselecting(projectID: "a", from: Set(items.keys), items: items)
        #expect(left == [URL(fileURLWithPath: "/c/b")])
    }

    // I6 — no libraries → no backup, cleanup refused
    @Test func noLibrariesRefused() {
        #expect(throws: LibraryBackup.BackupError.noLibraries) {
            try LibraryBackup.create(libraries: [], in: makeTempDir(), date: Date(), version: "1")
        }
    }
}
