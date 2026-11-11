import Foundation
import StorageCore

let args = CommandLine.arguments.dropFirst()
if args.first == "report" {
    let r = scanAll()
    print(renderReport(r.report))
    print("\n== Дублі LUT ==")
    for g in r.luts {
        print("\(g.copies.count) копії · зайве \(formatBytes(g.wasted))")
        for c in g.copies { print("   \(c.isSelectable ? "·" : "🔒") \(c.relativePath)\(c.usedBy.isEmpty ? "" : "  — використовується: " + c.usedBy.joined(separator: ", "))") }
    }
    print("Разом зайвого в LUT: \(formatBytes(r.luts.reduce(0) { $0 + $1.wasted }))")
} else {
    print("Використання: davinci-storage report")
    exit(args.isEmpty ? 0 : 1)
}
