import Foundation
import Testing
@testable import StorageCore

// MARK: Task 1 — settings

@Suite struct SettingsTests {
    @Test func defaultsWhenEmpty() {
        let d = UserDefaults(suiteName: "dvs-\(UUID().uuidString)")!
        let s = StorageSettings.load(d, home: URL(fileURLWithPath: "/Users/test"))
        #expect(s.backupFolder.path == "/Users/test/DAVINCI_DATA_BASE/_BACKUPS")
        #expect(s.keepLibraryBackups == 10)
        #expect(s.keepProjectBackups == 3)
        #expect(s.protectedProjectIDs.isEmpty)
    }

    @Test func roundTrip() {
        let d = UserDefaults(suiteName: "dvs-\(UUID().uuidString)")!
        var s = StorageSettings.load(d, home: URL(fileURLWithPath: "/Users/test"))
        s.backupFolder = URL(fileURLWithPath: "/Volumes/NAS/backups")
        s.keepLibraryBackups = 5
        s.keepProjectBackups = 2
        s.protectedProjectIDs = ["abc"]
        s.save(d)
        let r = StorageSettings.load(d, home: URL(fileURLWithPath: "/Users/test"))
        #expect(r.backupFolder.path == "/Volumes/NAS/backups")
        #expect(r.keepLibraryBackups == 5)
        #expect(r.keepProjectBackups == 2)
        #expect(r.protectedProjectIDs == ["abc"])
    }
}

// MARK: Task 2 — library backups

func makeLibrary(_ root: URL, name: String, files: [String: Int]) -> Library {
    for (rel, size) in files { makeFile(root.appendingPathComponent("Resolve Projects/" + rel), bytes: size) }
    return Library(name: name, root: root)
}

@Suite struct LibraryBackupTests {
    let date = ISO8601DateFormatter().date(from: "2026-11-11T18:05:00Z")!

    @Test func folderNameHasDateAndVersion() {
        let name = LibraryBackup.folderName(date: date, version: "21.2.0", timeZone: TimeZone(identifier: "Europe/Kiev")!)
        #expect(name == "2026-11-11 20-05 · DaVinci Resolve 21.2.0")
    }

    @Test func copiesOnlyResolveProjectsPerLibrary() throws {
        let tmp = makeTempDir()
        let main = makeLibrary(tmp.appendingPathComponent("DB"), name: "2026_new",
                               files: ["Users/guest/Projects/A/Project.db": 100])
        makeFile(tmp.appendingPathComponent("DB/_BACKUPS/old.txt"))      // must NOT be copied
        let course = makeLibrary(tmp.appendingPathComponent("DB/COURSE"), name: "COURSE",
                                 files: ["Users/guest/Projects/C/Project.db": 50])
        let out = try LibraryBackup.create(libraries: [main, course], in: tmp.appendingPathComponent("DB/_BACKUPS"),
                                           date: date, version: "21.2.0")
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: out.appendingPathComponent("2026_new/Resolve Projects/Users/guest/Projects/A/Project.db").path))
        #expect(fm.fileExists(atPath: out.appendingPathComponent("COURSE/Resolve Projects/Users/guest/Projects/C/Project.db").path))
        #expect(!fm.fileExists(atPath: out.appendingPathComponent("2026_new/Resolve Projects/../_BACKUPS").path))
        #expect(try fm.contentsOfDirectory(atPath: out.path).filter { !$0.hasPrefix(".") }.sorted() == ["2026_new", "COURSE"])
    }

    @Test func writesMarker() throws {
        let tmp = makeTempDir()
        let lib = makeLibrary(tmp.appendingPathComponent("DB"), name: "L", files: ["x/Project.db": 10])
        let out = try LibraryBackup.create(libraries: [lib], in: tmp.appendingPathComponent("B"), date: date, version: "21.2.0")
        let marker = try Data(contentsOf: out.appendingPathComponent(LibraryBackup.markerName))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let info = try dec.decode(LibraryBackup.Marker.self, from: marker)
        #expect(info.version == "21.2.0")
        #expect(info.libraries == ["L"])
    }

    @Test func refusesTargetInsideLibrary() {
        let tmp = makeTempDir()
        let lib = makeLibrary(tmp.appendingPathComponent("DB"), name: "L", files: ["x/Project.db": 10])
        #expect(throws: LibraryBackup.BackupError.targetInsideLibrary) {
            try LibraryBackup.create(libraries: [lib], in: tmp.appendingPathComponent("DB/Resolve Projects/backups"),
                                     date: date, version: "1")
        }
    }

    @Test func failedVerificationLeavesNothing() throws {
        let tmp = makeTempDir()
        let lib = makeLibrary(tmp.appendingPathComponent("DB"), name: "L", files: ["a/Project.db": 10, "b/Project.db": 10])
        let root = tmp.appendingPathComponent("B")
        let lossyCopy: (URL, URL) throws -> Void = { src, dst in
            try FileManager.default.copyItem(at: src, to: dst)
            try FileManager.default.removeItem(at: dst.appendingPathComponent("b/Project.db"))
        }
        #expect(throws: LibraryBackup.BackupError.self) {
            try LibraryBackup.create(libraries: [lib], in: root, date: date, version: "1", copy: lossyCopy,
                                     trash: { try FileManager.default.removeItem(at: $0) })
        }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).isEmpty)
    }

    @Test func uniqueNameWhenExists() throws {
        let tmp = makeTempDir()
        let lib = makeLibrary(tmp.appendingPathComponent("DB"), name: "L", files: ["x/Project.db": 10])
        let a = try LibraryBackup.create(libraries: [lib], in: tmp.appendingPathComponent("B"), date: date, version: "1")
        let b = try LibraryBackup.create(libraries: [lib], in: tmp.appendingPathComponent("B"), date: date, version: "1")
        #expect(a != b)
        #expect(b.lastPathComponent.hasSuffix(" (2)"))
    }

    @Test func rotationKeepsNewestN() throws {
        let tmp = makeTempDir(), root = tmp.appendingPathComponent("B")
        let lib = makeLibrary(tmp.appendingPathComponent("DB"), name: "L", files: ["x/Project.db": 10])
        var made: [URL] = []
        for i in 0..<4 {
            made.append(try LibraryBackup.create(libraries: [lib], in: root, date: date.addingTimeInterval(Double(i) * 3600), version: "1"))
        }
        var trashed: [URL] = []
        let removed = LibraryBackup.rotate(in: root, keep: 2, trash: { trashed.append($0) })
        #expect(Set(removed.map(\.lastPathComponent)) == Set(made.prefix(2).map(\.lastPathComponent)))
        #expect(trashed.count == 2)
    }

    @Test func rotationIgnoresForeignFolders() throws {
        let tmp = makeTempDir(), root = tmp.appendingPathComponent("B")
        makeFile(root.appendingPathComponent("2020-01-01 00-00 · DaVinci Resolve 18/foreign.txt"))   // no marker
        let lib = makeLibrary(tmp.appendingPathComponent("DB"), name: "L", files: ["x/Project.db": 10])
        _ = try LibraryBackup.create(libraries: [lib], in: root, date: date, version: "1")
        var trashed: [URL] = []
        _ = LibraryBackup.rotate(in: root, keep: 0, trash: { trashed.append($0) })
        #expect(!trashed.contains { $0.lastPathComponent.hasPrefix("2020-01-01") })
        #expect(trashed.count == 1)
    }

    @Test func versionFromInfoPlist() throws {
        let apps = makeTempDir()
        let contents = apps.appendingPathComponent("DaVinci Resolve/DaVinci Resolve.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": "21.2.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        #expect(LibraryBackup.resolveVersion(appsDir: apps) == "21.2.0")
        #expect(LibraryBackup.resolveVersion(appsDir: makeTempDir()) == "невідома версія")
    }
}

// MARK: Task 3 — project backup trimming

@Suite struct BackupTrimTests {
    func makeBackupDir() -> URL {
        let dir = makeTempDir().appendingPathComponent("585bbd4a-ba19-4d98-b863-18e2f5f4b8c0")
        for ts in ["20261109172354", "20261109173354", "20261109174355", "20261109175357"] {
            makeFile(dir.appendingPathComponent("Project.db.\(ts)"), bytes: 100)
        }
        for ts in ["20261109172018", "20261109173024", "20261109174035", "20261109175205"] {
            makeFile(dir.appendingPathComponent("96771795-50a5-44f3-9625-6f8da98c0ca6/Timeline.\(ts)"), bytes: 50)
        }
        makeFile(dir.appendingPathComponent("61dfb46c-7162-4f73-b1eb-59cbb0b21d5b.dpx"), bytes: 1000)
        return dir
    }

    @Test func keepsNewestNProjectDB() {
        let c = backupTrimCandidates(in: makeBackupDir(), keep: 3).map(\.lastPathComponent)
        #expect(c.filter { $0.hasPrefix("Project.db.") } == ["Project.db.20261109172354"])
    }

    @Test func keepsNewestNPerTimeline() {
        let c = backupTrimCandidates(in: makeBackupDir(), keep: 2).map(\.lastPathComponent).sorted()
        #expect(c == ["Project.db.20261109172354", "Project.db.20261109173354", "Timeline.20261109172018", "Timeline.20261109173024"])
    }

    @Test func leavesDpxAlone() {
        #expect(!backupTrimCandidates(in: makeBackupDir(), keep: 0).contains { $0.pathExtension == "dpx" })
    }

    @Test func protectedProjectSkipped() {
        let dir = makeBackupDir()
        let id = dir.lastPathComponent
        let r = analyze(projects: [project(id, "UKRAVIT")], unreadable: [],
                        items: [StorageItem(category: .backups, url: dir, bytes: 1, projectIDs: [id], match: .uuidFolder, label: "UKRAVIT")])
        #expect(backupTrimItems(r, keep: 1, protected: [id]).isEmpty)
        #expect(backupTrimItems(r, keep: 1, protected: []).count == 6)
    }

    @Test func deletedProjectsNotTrimmed() {
        let dir = makeBackupDir()
        let r = analyze(projects: [], unreadable: [],
                        items: [StorageItem(category: .backups, url: dir, bytes: 1, projectIDs: [dir.lastPathComponent], match: .uuidFolder, label: "x")])
        #expect(backupTrimItems(r, keep: 1, protected: []).isEmpty)
    }
}
