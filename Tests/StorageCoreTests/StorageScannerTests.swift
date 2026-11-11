import Foundation
import Testing
@testable import StorageCore

/// Locations laid out under a temp root, mirroring the real Mac.
func testLocations(_ root: URL) -> Locations {
    Locations(
        cacheRoots: [root.appendingPathComponent("Movies/CacheClip")],
        backupRoot: root.appendingPathComponent("Movies/Resolve Project Backups"),
        galleryProjectRoot: root.appendingPathComponent("Movies/.gallery"),
        galleryLegacyRoot: root.appendingPathComponent("Sys/.gallery"),
        magicMaskRoots: [root.appendingPathComponent("MAGIC_MASK_2_DAVINCI")],
        proxyRoots: [root.appendingPathComponent("Sys/ProxyMedia")],
        serviceItems: [ServiceLocation(label: "LUT-кеш (.LUT)", url: root.appendingPathComponent("U/.LUT"))])
}

func project(_ id: String, _ name: String, stills: Set<String> = [], masks: [URL] = []) -> Project {
    Project(id: id, name: name, library: "L", dbURL: URL(fileURLWithPath: "/tmp/\(name)/Project.db"),
            lastModified: Date(timeIntervalSince1970: 0), stillIDs: stills,
            magicMaskDirs: Set(masks.map(normalizedPath)))
}

@Suite struct StorageScannerTests {
    let uuid = "585bbd4a-ba19-4d98-b863-18e2f5f4b8c0"

    @Test func cacheFolderMappedByUUID() {
        let root = makeTempDir(), loc = testLocations(root)
        makeFile(loc.cacheRoots[0].appendingPathComponent("\(uuid)/a.bin"))
        let items = scanStorage(loc, projects: [project(uuid, "UKRAVIT")])
        let item = items.first { $0.category == .cache }
        #expect(item?.projectIDs == [uuid])
        #expect(item?.match == .uuidFolder)
        #expect(item?.label == "UKRAVIT")
    }

    @Test func backupFolderMappedByUUID() {
        let root = makeTempDir(), loc = testLocations(root)
        makeFile(loc.backupRoot!.appendingPathComponent("\(uuid)/Project.db.20261109173354"))
        let items = scanStorage(loc, projects: [])
        #expect(items.first { $0.category == .backups }?.projectIDs == [uuid])
    }

    @Test func nonUUIDCacheFoldersIgnored() {
        let root = makeTempDir(), loc = testLocations(root)
        makeFile(loc.cacheRoots[0].appendingPathComponent("audio/x.bin"))
        #expect(scanStorage(loc, projects: []).filter { $0.category == .cache }.isEmpty)
    }

    @Test func galleryInfoTxtGivesLabel() throws {
        let root = makeTempDir(), loc = testLocations(root)
        let dir = loc.galleryProjectRoot.appendingPathComponent("d442c79d-2443-4d4f-828c-84da21783bd8")
        makeFile(dir.appendingPathComponent("x.dpx"))
        try "Database Name: ARTveli_COLOR_COURSE\nUser Name: guest\nProject Name: COURSE_TEST\n"
            .write(to: dir.appendingPathComponent("Info.txt"), atomically: true, encoding: .utf8)
        let item = scanStorage(loc, projects: []).first { $0.category == .stills }
        #expect(item?.label == "COURSE_TEST")
        #expect(item?.projectIDs == ["d442c79d-2443-4d4f-828c-84da21783bd8"])
    }

    @Test func magicMaskAttributedByDbPathNotName() {
        let root = makeTempDir(), loc = testLocations(root)
        let maskDir = loc.magicMaskRoots[0].appendingPathComponent("АС27_ВШК_СГЕ/Magic Mask")
        makeFile(maskDir.appendingPathComponent("shot.mov"))
        let items = scanStorage(loc, projects: [project("fc", "FC27_DIR_CUT", masks: [maskDir])])
        let masks = items.filter { $0.category == .magicMask }
        #expect(masks.count == 1)
        #expect(masks.first?.projectIDs == ["fc"])
        #expect(masks.first?.match == .dbPath)
    }

    @Test func sharedMaskDirListsAllProjects() {
        let root = makeTempDir(), loc = testLocations(root)
        let maskDir = loc.magicMaskRoots[0].appendingPathComponent("UNDDER_ARMOR/Magic Mask")
        makeFile(maskDir.appendingPathComponent("shot.mov"))
        let items = scanStorage(loc, projects: [project("a", "UNDER_ARMOR", masks: [maskDir]),
                                                project("b", "UNDER_ARMOR_DIR_CUT", masks: [maskDir])])
        let masks = items.filter { $0.category == .magicMask }
        #expect(masks.count == 1)
        #expect(Set(masks.first?.projectIDs ?? []) == ["a", "b"])
    }

    @Test func unreferencedMagicMaskIsUnlinked() {
        let root = makeTempDir(), loc = testLocations(root)
        makeFile(loc.magicMaskRoots[0].appendingPathComponent("PROM_709/Magic Mask/shot.mov"))
        let item = scanStorage(loc, projects: []).first { $0.category == .magicMask }
        #expect(item?.match == .unlinked)
        #expect(item?.label == "PROM_709")
        #expect(item?.url.lastPathComponent == "PROM_709")
    }

    @Test func emptyMagicMaskFolderSkipped() throws {
        let root = makeTempDir(), loc = testLocations(root)
        try FileManager.default.createDirectory(at: loc.magicMaskRoots[0].appendingPathComponent("SAID_SPORT"),
                                                withIntermediateDirectories: true)
        #expect(scanStorage(loc, projects: []).isEmpty)
    }

    @Test func nfdPathMatchesNfcReference() {
        let root = makeTempDir(), loc = testLocations(root)
        let nfdName = "АС27_ВШК_СГЕ".decomposedStringWithCanonicalMapping
        makeFile(loc.magicMaskRoots[0].appendingPathComponent(nfdName).appendingPathComponent("Magic Mask/shot.mov"))
        let nfcDir = loc.magicMaskRoots[0].appendingPathComponent("АС27_ВШК_СГЕ".precomposedStringWithCanonicalMapping)
            .appendingPathComponent("Magic Mask")
        let masks = scanStorage(loc, projects: [project("fc", "FC27_DIR_CUT", masks: [nfcDir])])
            .filter { $0.category == .magicMask }
        #expect(masks.count == 1)
        #expect(masks.first?.match == .dbPath)
    }

    @Test func legacyStillMatchedByStillID() {
        let root = makeTempDir(), loc = testLocations(root)
        let still = "02259a23-ff34-41b7-b8e6-2ce9f970cccb"
        makeFile(loc.galleryLegacyRoot.appendingPathComponent("\(still).dpx"))
        makeFile(loc.galleryLegacyRoot.appendingPathComponent("ffffffff-ff34-41b7-b8e6-2ce9f970cccb.dpx"))
        let stills = scanStorage(loc, projects: [project(uuid, "UKRAVIT", stills: [still])]).filter { $0.category == .stills }
        #expect(stills.count == 2)
        #expect(stills.first { $0.match == .stillID }?.projectIDs == [uuid])
        #expect(stills.contains { $0.match == .unlinked })
    }

    @Test func proxyFolderMatchedByName() {
        let root = makeTempDir(), loc = testLocations(root)
        makeFile(loc.proxyRoots[0].appendingPathComponent("ukravit/clip.mov"))
        let item = scanStorage(loc, projects: [project(uuid, "UKRAVIT")]).first { $0.category == .proxy }
        #expect(item?.match == .byName)
        #expect(item?.projectIDs == [uuid])
    }

    @Test func serviceItemReported() {
        let root = makeTempDir(), loc = testLocations(root)
        makeFile(loc.serviceItems[0].url.appendingPathComponent("1_DWG/x_shaperlut"))
        let item = scanStorage(loc, projects: []).first { $0.category == .service }
        #expect(item?.label == "LUT-кеш (.LUT)")
        #expect(item?.projectIDs.isEmpty == true)
    }
}
