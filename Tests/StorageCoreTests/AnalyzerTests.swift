import Foundation
import Testing
@testable import StorageCore

func item(_ c: StorageCore.Category, _ path: String, _ bytes: Int64, _ ids: [String], _ m: MatchKind = .uuidFolder, _ label: String = "x") -> StorageItem {
    StorageItem(category: c, url: URL(fileURLWithPath: path), bytes: bytes, projectIDs: ids, match: m, label: label)
}

@Suite struct AnalyzerTests {
    @Test func itemsGroupedIntoProjectRows() {
        let r = analyze(projects: [project("a", "A")], unreadable: [], items: [
            item(.cache, "/c/a", 100, ["a"]), item(.backups, "/b/a", 20, ["a"]), item(.cache, "/c2/a", 5, ["a"]),
        ])
        #expect(r.rows.count == 1)
        #expect(r.rows[0].bytes[.cache] == 105)
        #expect(r.rows[0].bytes[.backups] == 20)
        #expect(r.rows[0].total == 125)
        #expect(r.deleted.isEmpty)
    }

    @Test func projectWithoutItemsStillListed() {
        let r = analyze(projects: [project("a", "A")], unreadable: [], items: [])
        #expect(r.rows.map(\.project.name) == ["A"])
        #expect(r.rows[0].total == 0)
    }

    @Test func unknownUUIDGoesToDeleted() {
        let r = analyze(projects: [project("a", "A")], unreadable: [], items: [
            item(.cache, "/c/zzz", 10, ["zzz"]), item(.backups, "/b/zzz", 5, ["zzz"]),
        ])
        #expect(r.deleted.count == 1)
        #expect(r.deleted[0].total == 15)
        #expect(r.deleted[0].items.count == 2)
        #expect(r.deleted[0].uncertain == false)
    }

    @Test func unlinkedFolderGoesToDeleted() {
        let r = analyze(projects: [], unreadable: [], items: [item(.magicMask, "/mm/PROM_709", 50, [], .unlinked, "PROM_709")])
        #expect(r.deleted.map(\.title) == ["PROM_709"])
    }

    @Test func sharedItemCountedOnce() {
        let r = analyze(projects: [project("a", "A"), project("b", "B")], unreadable: [],
                        items: [item(.magicMask, "/mm/UA/Magic Mask", 100, ["a", "b"], .dbPath)])
        #expect(r.rows.allSatisfy { $0.total == 100 })
        #expect(r.grandTotal == 100)
    }

    @Test func serviceItemsSeparate() {
        let r = analyze(projects: [], unreadable: [], items: [item(.service, "/u/.LUT", 7, [], .unlinked, "LUT")])
        #expect(r.service.count == 1)
        #expect(r.deleted.isEmpty)
        #expect(r.grandTotal == 7)
    }

    @Test func magicMaskCopyDetectedAsDuplicate() {
        let root = makeTempDir()
        let original = root.appendingPathComponent("Media/UKRAVIT/Magic Mask")
        let copy = root.appendingPathComponent("MM2/UKRAVIT")
        for n in ["s1.mov", "s2.mov", "s3.mov"] {
            makeFile(original.appendingPathComponent(n))
            makeFile(copy.appendingPathComponent("Magic Mask/\(n)"))
        }
        let r = analyze(projects: [project("u", "UKRAVIT")], unreadable: [], items: [
            StorageItem(category: .magicMask, url: original, bytes: 3, projectIDs: ["u"], match: .dbPath, label: "UKRAVIT"),
            StorageItem(category: .magicMask, url: copy, bytes: 3, projectIDs: [], match: .unlinked, label: "UKRAVIT"),
        ])
        #expect(r.duplicates.count == 1)
        #expect(r.duplicates[0].items.first?.url == copy)
        #expect(r.deleted.isEmpty)
    }

    @Test func differentFilesAreNotDuplicate() {
        let root = makeTempDir()
        let original = root.appendingPathComponent("A/Magic Mask")
        let other = root.appendingPathComponent("B")
        makeFile(original.appendingPathComponent("s1.mov"))
        makeFile(other.appendingPathComponent("Magic Mask/other.mov"))
        let r = analyze(projects: [project("a", "A")], unreadable: [], items: [
            StorageItem(category: .magicMask, url: original, bytes: 1, projectIDs: ["a"], match: .dbPath, label: "A"),
            StorageItem(category: .magicMask, url: other, bytes: 1, projectIDs: [], match: .unlinked, label: "B"),
        ])
        #expect(r.duplicates.isEmpty)
        #expect(r.deleted.count == 1)
    }

    @Test func unreadableProjectMakesDeletedUncertain() {
        let r = analyze(projects: [], unreadable: [URL(fileURLWithPath: "/lib/X/Project.db")],
                        items: [item(.cache, "/c/zzz", 10, ["zzz"])])
        #expect(r.deleted.first?.uncertain == true)
    }
}
