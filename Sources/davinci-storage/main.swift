import Foundation
import StorageCore

let args = CommandLine.arguments.dropFirst()
if args.first == "report" {
    print(renderReport(scanAll().report))
} else {
    print("Використання: davinci-storage report")
    exit(args.isEmpty ? 0 : 1)
}
