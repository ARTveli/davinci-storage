import Foundation

public enum ResolveConfigParser {
    /// `dblist.conf`: one library per line, `name:path:...:TYPE`. Only disk libraries are returned.
    public static func parseDBList(_ text: String) -> [Library] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, fields.last == "DISK", !fields[1].isEmpty else { return nil }
            return Library(name: fields[0], root: URL(fileURLWithPath: fields[1], isDirectory: true))
        }
    }

    /// `<ProjectBackupLocation>` from `config.user.xml`, trimmed; nil when absent or empty.
    public static func parseBackupLocation(_ xml: String) -> String? {
        guard let open = xml.range(of: "<ProjectBackupLocation>"),
              let close = xml.range(of: "</ProjectBackupLocation>", range: open.upperBound..<xml.endIndex)
        else { return nil }
        let value = xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Reads `dblist.conf` and `config.user.xml` from Resolve's preferences folder.
    public static func load(prefsDir: URL) throws -> ResolveConfig {
        let dblist = try String(contentsOf: prefsDir.appendingPathComponent("dblist.conf"), encoding: .utf8)
        let userXML = (try? String(contentsOf: prefsDir.appendingPathComponent("config.user.xml"), encoding: .utf8)) ?? ""
        let backup = parseBackupLocation(userXML).map { URL(fileURLWithPath: $0, isDirectory: true) }
        return ResolveConfig(libraries: parseDBList(dblist), backupRoot: backup)
    }
}
