import Foundation
import Testing
@testable import StorageCore

@Suite struct ResolveConfigTests {
    @Test func parseDBListReadsDiskLibraries() {
        let text = "2026_new:/Users/artveli/DAVINCI_DATA_BASE:*:::DISK\nARTveli_COLOR_COURSE:/Users/artveli/DAVINCI_DATA_BASE/ARTveli_COLOR_COURSE::::DISK\nPG:host:5432:::PG\n"
        let libs = ResolveConfigParser.parseDBList(text)
        #expect(libs.map(\.name) == ["2026_new", "ARTveli_COLOR_COURSE"])
        #expect(libs.map(\.root.path) == ["/Users/artveli/DAVINCI_DATA_BASE",
                                          "/Users/artveli/DAVINCI_DATA_BASE/ARTveli_COLOR_COURSE"])
    }

    @Test func parseBackupLocationTrimsNewline() {
        let xml = "<a><ProjectBackupLocation>/Users/artveli/Movies/Resolve Project Backups\n</ProjectBackupLocation></a>"
        #expect(ResolveConfigParser.parseBackupLocation(xml) == "/Users/artveli/Movies/Resolve Project Backups")
    }

    @Test func parseBackupLocationMissingIsNil() {
        #expect(ResolveConfigParser.parseBackupLocation("<a><ProjectBackupLocation/></a>") == nil)
        #expect(ResolveConfigParser.parseBackupLocation("<a></a>") == nil)
    }
}
