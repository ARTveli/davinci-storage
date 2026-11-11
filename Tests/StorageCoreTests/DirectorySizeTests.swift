import Foundation
import Testing
@testable import StorageCore

@Suite struct DirectorySizeTests {
    @Test func sizeOfMissingIsZero() {
        #expect(allocatedSize(of: makeTempDir().appendingPathComponent("missing")) == 0)
    }

    @Test func sizeSumsNestedFiles() {
        let dir = makeTempDir()
        makeFile(dir.appendingPathComponent("a/one.bin"))
        makeFile(dir.appendingPathComponent("a/b/two.bin"))
        #expect(allocatedSize(of: dir) >= 8192)
    }

    @Test func sizeOfSingleFile() {
        let f = makeFile(makeTempDir().appendingPathComponent("x.bin"))
        #expect(allocatedSize(of: f) >= 4096)
    }

    @Test func realLocationsUseResolveDefaults() {
        let home = URL(fileURLWithPath: "/Users/test")
        let cfg = ResolveConfig(libraries: [], backupRoot: URL(fileURLWithPath: "/Users/test/Movies/Resolve Project Backups"))
        let loc = Locations.real(home: home, config: cfg)
        #expect(loc.cacheRoots.map(\.path).contains("/Users/test/Movies/CacheClip"))
        #expect(loc.magicMaskRoots.map(\.path).contains("/Users/test/MAGIC_MASK_2_DAVINCI"))
        #expect(loc.proxyRoots.map(\.path).contains("/Library/Application Support/Blackmagic Design/DaVinci Resolve/ProxyMedia"))
        #expect(loc.serviceItems.map(\.url.lastPathComponent).contains(".LUT"))
        #expect(loc.backupRoot?.path == "/Users/test/Movies/Resolve Project Backups")
    }
}
