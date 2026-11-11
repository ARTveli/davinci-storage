import Foundation
import Testing
@testable import StorageCore

// MARK: Task 4 — Magic Mask setting + protected projects

@Suite struct MaskSettingAndProtectedTests {
    @Test func configuredMaskRootsRead() throws {
        let db = makeTempDir().appendingPathComponent("Project.db")
        try makeProjectDB(at: db, id: "k", name: "KORAIL_MAQUETTE", lastMod: 1)
        try addConfigBlob(db, configFields(mask: "/Users/artveli/KORAIL_MAQUETTE"))
        let p = try ProjectReader.read(dbURL: db, library: "L").get()
        #expect(p.configuredMaskRoots == ["/Users/artveli/KORAIL_MAQUETTE"])
    }

    @Test func oldSelectionSkipsProtectedAndShared() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        func p(_ id: String) -> Project {
            Project(id: id, name: id, library: "L", dbURL: URL(fileURLWithPath: "/\(id)"), lastModified: old, stillIDs: [], magicMaskDirs: [])
        }
        let r = analyze(projects: [p("a"), p("b"), p("c")], unreadable: [], items: [
            item(.cache, "/c/a", 1, ["a"]),                       // a protected → no
            item(.magicMask, "/mm/ab", 1, ["a", "b"], .dbPath),   // shared with protected a → no
            item(.cache, "/c/c", 1, ["c"]),                       // → yes
        ])
        #expect(oldSelection(r, months: 3, now: now, protected: ["a"]).map(\.path) == ["/c/c"])
    }
}

// MARK: Task 5 — LUT duplicates

@Suite struct LutDuplicateTests {
    func write(_ url: URL, _ text: String) {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func groupsIdenticalContentDifferentNames() {
        let root = makeTempDir()
        let body = "LUT_3D_SIZE 2\n0 0 0\n1 1 1\n"
        write(root.appendingPathComponent("PackA/Look.cube"), body)
        write(root.appendingPathComponent("PackB/Look copy.cube"), body)
        write(root.appendingPathComponent("PackC/Other.cube"), body + "x")
        let groups = findLutDuplicates(root: root)
        #expect(groups.count == 1)
        #expect(Set(groups[0].copies.map(\.relativePath)) == ["PackA/Look.cube", "PackB/Look copy.cube"])
        #expect(groups[0].wasted == groups[0].copies[0].bytes)
    }

    @Test func differentContentNotDuplicate() {
        let root = makeTempDir()
        write(root.appendingPathComponent("A/x.cube"), "1")
        write(root.appendingPathComponent("B/x.cube"), "2")
        #expect(findLutDuplicates(root: root).isEmpty)
    }

    @Test func nonLutFilesIgnored() {
        let root = makeTempDir()
        write(root.appendingPathComponent("A/x.png"), "1")
        write(root.appendingPathComponent("B/y.png"), "1")
        #expect(findLutDuplicates(root: root).isEmpty)
    }

    @Test func referenceFoundInProjectBlob() throws {
        let db = makeTempDir().appendingPathComponent("Project.db")
        let ref = Array("\n\u{1d}1_DWG/4_Art_LUT_DWG/Look.cube\u{12}".utf8)
        try makeProjectDB(at: db, id: "u", name: "UKRAVIT", lastMod: 1, clipBlobs: [ref])
        let p = try ProjectReader.read(dbURL: db, library: "L").get()
        let refs = lutReferences(projects: [p])
        #expect(refs.keys.contains { $0.hasSuffix("look.cube") })
    }

    @Test func usedLutNotSelectable() throws {
        let root = makeTempDir()
        write(root.appendingPathComponent("1_DWG/4_Art_LUT_DWG/Look.cube"), "same")
        write(root.appendingPathComponent("9_TEST_LUT/Look_dup.cube"), "same")
        let refs: [String: Set<String>] = ["1_dwg/4_art_lut_dwg/look.cube": ["UKRAVIT"]]
        let g = markUsage(findLutDuplicates(root: root), refs: refs)[0]
        let used = g.copies.first { $0.relativePath.hasPrefix("1_DWG") }!
        let free = g.copies.first { $0.relativePath.hasPrefix("9_TEST") }!
        #expect(used.usedBy == ["UKRAVIT"])
        #expect(!used.isSelectable)
        #expect(free.usedBy.isEmpty)
        #expect(free.isSelectable)
    }

    @Test func lutUnderDctlFolderNotSelectable() {
        let root = makeTempDir()
        write(root.appendingPathComponent("DCTL/Looks/Pack/look.dctle"), "binary")
        write(root.appendingPathComponent("DCTL/Looks/Pack/.resources/base/City.cube"), "same")
        write(root.appendingPathComponent("1_DWG/City_Final.cube"), "same")
        let g = markUsage(findLutDuplicates(root: root), refs: dctlReferences(root: root))[0]
        let inDctl = g.copies.first { $0.relativePath.hasPrefix("DCTL") }!
        let plain = g.copies.first { $0.relativePath.hasPrefix("1_DWG") }!
        #expect(!inDctl.isSelectable)
        #expect(inDctl.usedBy == ["DCTL · Pack"])
        #expect(plain.isSelectable)
    }

    @Test func lutNamedInsideDctlSourceIsUsed() {
        let root = makeTempDir()
        write(root.appendingPathComponent("Scripts/grade.dctl"), "DEFINE_LUT(Film, ../LUTs/Film.cube)")
        write(root.appendingPathComponent("LUTs/Film.cube"), "same")
        write(root.appendingPathComponent("Other/Film copy.cube"), "same")
        let g = markUsage(findLutDuplicates(root: root), refs: dctlReferences(root: root))[0]
        #expect(g.copies.first { $0.relativePath == "LUTs/Film.cube" }?.isSelectable == false)
    }

    @Test func sameFileNameElsewhereCountsAsUsed() {
        let root = makeTempDir()
        write(root.appendingPathComponent("A/Look.cube"), "same")
        write(root.appendingPathComponent("B/Look.cube"), "same")
        let g = markUsage(findLutDuplicates(root: root), refs: ["somewhere/else/look.cube": ["P"]])[0]
        #expect(g.copies.allSatisfy { !$0.isSelectable })
    }
}

// MARK: Task 6 — logs and crash reports

@Suite struct OtherLeftoversTests {
    @Test func crashReportsListedOnlyIfPresent() {
        let root = makeTempDir()
        var loc = testLocations(root)
        loc.crashReportsDir = root.appendingPathComponent("DiagnosticReports")
        #expect(scanStorage(loc, projects: []).filter { $0.label.contains("збій") }.isEmpty)
        makeFile(loc.crashReportsDir!.appendingPathComponent("Resolve-2026-11-09-151100.ips"))
        makeFile(loc.crashReportsDir!.appendingPathComponent("Safari-2026-11-09.ips"))
        let crashes = scanStorage(loc, projects: []).filter { $0.label.contains("збій") }
        #expect(crashes.count == 1)
        #expect(crashes[0].category == .service)
    }

    @Test func logsAreAServiceLocation() {
        let loc = Locations.real(home: URL(fileURLWithPath: "/Users/t"), config: ResolveConfig(libraries: [], backupRoot: nil))
        #expect(loc.serviceItems.contains { $0.url.lastPathComponent == "logs" && $0.label == "Логи DaVinci" })
        #expect(loc.lutRoot?.lastPathComponent == "LUT")
        #expect(loc.crashReportsDir?.path == "/Users/t/Library/Logs/DiagnosticReports")
    }
}

@Suite struct SelectableItemsTests {
    @Test func includesTrimItemsAndOnlyFreeLutCopies() {
        let dir = makeTempDir().appendingPathComponent("585bbd4a-ba19-4d98-b863-18e2f5f4b8c0")
        for ts in ["20261109172354", "20261109173354"] { makeFile(dir.appendingPathComponent("Project.db.\(ts)")) }
        let id = dir.lastPathComponent
        let report = analyze(projects: [project(id, "U")], unreadable: [],
                             items: [StorageItem(category: .backups, url: dir, bytes: 1, projectIDs: [id], match: .uuidFolder, label: "U")])
        let lutRoot = makeTempDir()
        let free = LutCopy(url: lutRoot.appendingPathComponent("a.cube"), relativePath: "a.cube", bytes: 5)
        var used = LutCopy(url: lutRoot.appendingPathComponent("b.cube"), relativePath: "b.cube", bytes: 5)
        used.usedBy = ["P"]
        var r = ScanResult(report: report, locations: testLocations(makeTempDir()), projects: [project(id, "U")], libraryRoots: [])
        r.luts = [LutGroup(id: "h", copies: [free, used])]
        let paths = Set(r.selectableItems(keepProjectBackups: 1, protected: []).map { $0.url.resolvingSymlinksInPath().path })
        func has(_ u: URL) -> Bool { paths.contains(u.resolvingSymlinksInPath().path) }
        #expect(has(dir.appendingPathComponent("Project.db.20261109172354")))
        #expect(!has(dir.appendingPathComponent("Project.db.20261109173354")))
        #expect(has(free.url))
        #expect(!has(used.url))
        #expect(has(dir))
    }
}
