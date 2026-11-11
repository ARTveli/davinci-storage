import Foundation
import Testing
@testable import StorageCore

@Suite struct ReportPrinterTests {
    @Test func rendersSectionsAndTotals() {
        let r = analyze(projects: [project("a", "UKRAVIT")], unreadable: [], items: [
            item(.cache, "/c/a", 2_000_000_000, ["a"]),
            item(.magicMask, "/mm/PROM_709", 500_000_000, [], .unlinked, "PROM_709"),
            item(.service, "/u/.LUT", 100_000_000, [], .unlinked, "LUT-кеш (.LUT)"),
        ])
        let text = renderReport(r)
        for needle in ["Проєкти", "Видалені проєкти і дублі", "Службові кеші", "UKRAVIT", "PROM_709", "LUT-кеш (.LUT)",
                       formatBytes(2_600_000_000)] {
            #expect(text.contains(needle), "missing \(needle)")
        }
    }

    @Test func emptyProjectShowsDashNotZero() {
        let r = analyze(projects: [project("a", "EMPTY")], unreadable: [], items: [])
        #expect(!renderReport(r).contains("Zero"))
        #expect(formatBytes(0) == "—")
    }

    @Test func unreadableProjectsWarned() {
        let r = analyze(projects: [], unreadable: [URL(fileURLWithPath: "/lib/X/Project.db")], items: [])
        #expect(renderReport(r).contains("/lib/X/Project.db"))
    }
}
