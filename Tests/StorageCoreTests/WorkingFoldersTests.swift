import Foundation
import SQLite3
import Testing
@testable import StorageCore

/// Bytes shaped like Resolve's SM_Config.FieldsBlob: protobuf fields 124 (Magic Mask), 39 (cache), 40 (proxy).
func configFields(mask: String? = nil, cache: String? = nil, proxy: String? = nil) -> [UInt8] {
    func field(_ tag: [UInt8], _ s: String) -> [UInt8] {
        let b = Array(s.utf8)
        var len: [UInt8] = []
        var n = b.count
        repeat { var byte = UInt8(n & 0x7F); n >>= 7; if n > 0 { byte |= 0x80 }; len.append(byte) } while n > 0
        return tag + len + b
    }
    var out: [UInt8] = [0xF2, 0x05, 0x04] + Array("ap4h".utf8)
    if let mask { out += field([0xE2, 0x07], mask) }
    if let cache { out += field([0xBA, 0x02], cache) }
    if let proxy { out += field([0xC2, 0x02], proxy) }
    return out + [0x90, 0x08, 0xC6, 0x20]
}

@Suite struct WorkingFoldersTests {
    @Test func extractsAllThreeFolders() {
        let f = ProjectReader.extractWorkingFolders(from: configFields(
            mask: "/Users/artveli/MAGIC_MASK_2_DAVINCI/UKRAVIT",
            cache: "/Users/artveli/Movies/CacheClip",
            proxy: "/Library/Application Support/Blackmagic Design/DaVinci Resolve/ProxyMedia"))
        #expect(f.magicMaskRoots == ["/Users/artveli/MAGIC_MASK_2_DAVINCI/UKRAVIT"])
        #expect(f.cacheRoots == ["/Users/artveli/Movies/CacheClip"])
        #expect(f.proxyRoots == ["/Library/Application Support/Blackmagic Design/DaVinci Resolve/ProxyMedia"])
    }

    @Test func longPathUsesTwoByteLength() {
        let long = "/Users/artveli/" + String(repeating: "x", count: 150)
        #expect(ProjectReader.extractWorkingFolders(from: configFields(mask: long)).magicMaskRoots == [long])
    }

    @Test func cyrillicFolderSurvives() {
        let p = "/Users/artveli/MAGIC_MASK_2_DAVINCI/АС27_ВШК_СГЕ"
        #expect(ProjectReader.extractWorkingFolders(from: configFields(mask: p)).magicMaskRoots == [p])
    }

    @Test func projectSettingAddsMagicMaskDir() throws {
        let db = makeTempDir().appendingPathComponent("Project.db")
        try makeProjectDB(at: db, id: "u", name: "UKRAVIT", lastMod: 1,
                          clipBlobs: [clipBlob(dir: "/Users/artveli/DaVinci Resolve Media/UKRAVIT/Magic Mask")])
        try addConfigBlob(db, configFields(mask: "/Users/artveli/MAGIC_MASK_2_DAVINCI/UKRAVIT", cache: "/Volumes/SSD/CacheClip"))
        let p = try ProjectReader.read(dbURL: db, library: "L").get()
        #expect(p.magicMaskDirs == ["/Users/artveli/DaVinci Resolve Media/UKRAVIT/Magic Mask",
                                    "/Users/artveli/MAGIC_MASK_2_DAVINCI/UKRAVIT/Magic Mask"])
        #expect(p.cacheRoots == ["/Volumes/SSD/CacheClip"])
    }

    @Test func projectCacheRootIsScanned() {
        let root = makeTempDir(), loc = testLocations(root)
        let custom = root.appendingPathComponent("SSD/CacheClip")
        let id = "585bbd4a-ba19-4d98-b863-18e2f5f4b8c0"
        makeFile(custom.appendingPathComponent("\(id)/a.bin"))
        var p = project(id, "UKRAVIT")
        p.cacheRoots = [normalizedPath(custom)]
        let item = scanStorage(loc, projects: [p]).first { $0.category == .cache }
        #expect(item?.projectIDs == [id])
    }
}

func addConfigBlob(_ db: URL, _ blob: [UInt8]) throws {
    var h: OpaquePointer?
    guard sqlite3_open(db.path, &h) == SQLITE_OK else { throw NSError(domain: "fixture", code: 3) }
    defer { sqlite3_close(h) }
    sqlite3_exec(h, "CREATE TABLE SM_Config (FieldsBlob blob)", nil, nil, nil)
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(h, "INSERT INTO SM_Config VALUES (?)", -1, &stmt, nil)
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    blob.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(blob.count), transient) }
    sqlite3_step(stmt)
    sqlite3_finalize(stmt)
}
