import Foundation
import Testing
@testable import StorageCore

@Suite struct ProjectReaderTests {
    @Test func readsIdNameAndDate() throws {
        let db = makeTempDir().appendingPathComponent("Project.db")
        try makeProjectDB(at: db, id: "585BBD4A-BA19-4D98-B863-18E2F5F4B8C0", name: "UKRAVIT", lastMod: 1794331426)
        let p = try ProjectReader.read(dbURL: db, library: "2026_new").get()
        #expect(p.id == "585bbd4a-ba19-4d98-b863-18e2f5f4b8c0")
        #expect(p.name == "UKRAVIT")
        #expect(p.library == "2026_new")
        #expect(p.lastModified == Date(timeIntervalSince1970: 1794331426))
    }

    @Test func readsStillIDs() throws {
        let db = makeTempDir().appendingPathComponent("Project.db")
        try makeProjectDB(at: db, id: "a", name: "A", lastMod: 0,
                          stillIDs: ["02259A23-FF34-41B7-B8E6-2CE9F970CCCB", "2e476cb8-a0a4-411c-98ba-f1a496148aa4"])
        let p = try ProjectReader.read(dbURL: db, library: "L").get()
        #expect(p.stillIDs == ["02259a23-ff34-41b7-b8e6-2ce9f970cccb", "2e476cb8-a0a4-411c-98ba-f1a496148aa4"])
    }

    @Test func extractsMagicMaskDirFromBlob() {
        let blob = clipBlob(dir: "/Users/artveli/DaVinci Resolve Media/UKRAVIT/Magic Mask", file: "Ukravit_02.mov")
        #expect(ProjectReader.extractMagicMaskDirs(from: blob) == ["/Users/artveli/DaVinci Resolve Media/UKRAVIT/Magic Mask"])
    }

    @Test func extractsCyrillicMagicMaskDir() {
        let blob = clipBlob(dir: "/Users/artveli/MAGIC_MASK_2_DAVINCI/АС27_ВШК_СГЕ/Magic Mask")
        #expect(ProjectReader.extractMagicMaskDirs(from: blob) == ["/Users/artveli/MAGIC_MASK_2_DAVINCI/АС27_ВШК_СГЕ/Magic Mask"])
    }

    @Test func magicMaskDirsComeFromClipTable() throws {
        let db = makeTempDir().appendingPathComponent("Project.db")
        try makeProjectDB(at: db, id: "a", name: "A", lastMod: 0,
                          clipBlobs: [clipBlob(dir: "/Users/x/MM/A/Magic Mask"), clipBlob(dir: "/Users/x/MM/A/Magic Mask")])
        let p = try ProjectReader.read(dbURL: db, library: "L").get()
        #expect(p.magicMaskDirs == ["/Users/x/MM/A/Magic Mask"])
    }

    @Test func missingFileIsError() {
        let url = makeTempDir().appendingPathComponent("nope/Project.db")
        guard case .failure = ProjectReader.read(dbURL: url, library: "L") else {
            Issue.record("expected failure"); return
        }
    }

    @Test func findsNestedProjects() throws {
        let root = makeTempDir()
        let projects = root.appendingPathComponent("Resolve Projects/Users/guest/Projects")
        try makeProjectDB(at: projects.appendingPathComponent("AD/A/Project.db"), id: "a", name: "A", lastMod: 0)
        try makeProjectDB(at: projects.appendingPathComponent("B/Project.db"), id: "b", name: "B", lastMod: 0)
        let found = ProjectReader.findProjectDBs(in: Library(name: "L", root: root))
        #expect(found.count == 2)
    }

    @Test func readDoesNotModifyDB() throws {
        let db = makeTempDir().appendingPathComponent("Project.db")
        try makeProjectDB(at: db, id: "a", name: "A", lastMod: 0, stillIDs: ["s"], clipBlobs: [clipBlob(dir: "/Users/x/Magic Mask")])
        let before = try Data(contentsOf: db)
        let mtime = try FileManager.default.attributesOfItem(atPath: db.path)[.modificationDate] as? Date
        _ = ProjectReader.read(dbURL: db, library: "L")
        #expect(try Data(contentsOf: db) == before)
        #expect(try FileManager.default.attributesOfItem(atPath: db.path)[.modificationDate] as? Date == mtime)
    }
}
