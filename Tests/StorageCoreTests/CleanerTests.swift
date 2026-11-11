import Foundation
import Testing
@testable import StorageCore

final class TrashRecorder: @unchecked Sendable {
    var urls: [URL] = []
}

@Suite struct CleanerTests {
    func setup() -> (root: URL, cleaner: Cleaner, recorder: TrashRecorder) {
        let root = makeTempDir()
        let rec = TrashRecorder()
        let cleaner = Cleaner(allowedRoots: [root.appendingPathComponent("CacheClip")],
                              allowedItems: [root.appendingPathComponent("U/.LUT")],
                              libraryRoots: [root.appendingPathComponent("CacheClip/DB")],
                              trash: { rec.urls.append($0) })
        return (root, cleaner, rec)
    }

    @Test func refusesOutsideRoots() {
        let (root, cleaner, _) = setup()
        let f = makeFile(root.appendingPathComponent("Documents/a.bin"))
        #expect(cleaner.validate(f) == .outsideAllowedRoots)
    }

    @Test func refusesRootItself() {
        let (root, cleaner, _) = setup()
        makeFile(root.appendingPathComponent("CacheClip/x/a.bin"))
        #expect(cleaner.validate(root.appendingPathComponent("CacheClip")) == .isRoot)
    }

    @Test func refusesInsideLibrary() {
        let (root, cleaner, _) = setup()
        let db = makeFile(root.appendingPathComponent("CacheClip/DB/Resolve Projects/Project.db"))
        #expect(cleaner.validate(db) == .insideLibrary)
    }

    @Test func refusesSymlinkEscapingRoot() throws {
        let (root, cleaner, _) = setup()
        let outside = makeFile(root.appendingPathComponent("Documents/secret.bin"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("CacheClip"), withIntermediateDirectories: true)
        let link = root.appendingPathComponent("CacheClip/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(cleaner.validate(link) == .outsideAllowedRoots)
    }

    @Test func allowsExactServiceItem() {
        let (root, cleaner, _) = setup()
        makeFile(root.appendingPathComponent("U/.LUT/x_shaperlut"))
        #expect(cleaner.validate(root.appendingPathComponent("U/.LUT")) == nil)
    }

    @Test func trashesAllowedItem() {
        let (root, cleaner, rec) = setup()
        let dir = root.appendingPathComponent("CacheClip/585bbd4a-ba19-4d98-b863-18e2f5f4b8c0")
        makeFile(dir.appendingPathComponent("a.bin"))
        let result = cleaner.clean([dir])
        #expect(result.trashed.count == 1)
        #expect(rec.urls.map(normalizedPath) == [normalizedPath(dir)])
    }

    @Test func missingItemReportedAsFailure() throws {
        let (root, cleaner, rec) = setup()
        let a = root.appendingPathComponent("CacheClip/a")
        let b = root.appendingPathComponent("CacheClip/b")
        makeFile(a.appendingPathComponent("x.bin"))
        makeFile(b.appendingPathComponent("x.bin"))
        try FileManager.default.removeItem(at: b)
        let result = cleaner.clean([a, b])
        #expect(result.trashed.count == 1)
        #expect(result.failed.count == 1)
        #expect(rec.urls.count == 1)
    }

    @Test func refusedItemNeverReachesTrash() {
        let (root, cleaner, rec) = setup()
        let f = makeFile(root.appendingPathComponent("Documents/a.bin"))
        let result = cleaner.clean([f])
        #expect(result.failed.count == 1)
        #expect(rec.urls.isEmpty)
    }
}
