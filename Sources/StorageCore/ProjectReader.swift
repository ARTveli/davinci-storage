import Foundation
import SQLite3

public enum ProjectReadError: Error, Equatable {
    case open(String), query(String), noProjectRow
}

/// Reads Resolve disk-database projects. Databases are opened strictly read-only.
public enum ProjectReader {
    /// `<library>/Resolve Projects/Users/*/Projects/**/Project.db`
    public static func findProjectDBs(in library: Library) -> [URL] {
        let fm = FileManager.default
        let usersDir = library.root.appendingPathComponent("Resolve Projects/Users", isDirectory: true)
        guard let users = try? fm.contentsOfDirectory(at: usersDir, includingPropertiesForKeys: nil) else { return [] }
        var result: [URL] = []
        for user in users {
            let projects = user.appendingPathComponent("Projects", isDirectory: true)
            guard let walker = fm.enumerator(at: projects, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.lastPathComponent == "Project.db" {
                result.append(url)
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    public static func read(dbURL: URL, library: String) -> Result<Project, ProjectReadError> {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return .failure(.open("file not found")) }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            return .failure(.open(msg))
        }
        defer { sqlite3_close(db) }

        var row: (String, String, Int64)?
        let ok = query(db, "SELECT SM_Project_id, ProjectName, LastModTimeInSecs FROM SM_Project LIMIT 1") { stmt in
            row = (text(stmt, 0), text(stmt, 1), sqlite3_column_int64(stmt, 2))
        }
        guard ok else { return .failure(.query(String(cString: sqlite3_errmsg(db)))) }
        guard let (id, name, lastMod) = row, !id.isEmpty else { return .failure(.noProjectRow) }

        var stills = Set<String>()
        _ = query(db, "SELECT \"Gallery::GyStill_id\" FROM \"Gallery::GyStill\"") { stmt in
            stills.insert(text(stmt, 0).lowercased())
        }
        var masks = Set<String>()
        _ = query(db, "SELECT Clip FROM BtVideoInfo") { stmt in
            guard let ptr = sqlite3_column_blob(stmt, 0) else { return }
            let count = Int(sqlite3_column_bytes(stmt, 0))
            let bytes = Array(UnsafeRawBufferPointer(start: ptr, count: count))
            masks.formUnion(extractMagicMaskDirs(from: bytes))
        }
        return .success(Project(id: id.lowercased(), name: name, library: library, dbURL: dbURL,
                                lastModified: Date(timeIntervalSince1970: TimeInterval(lastMod)),
                                stillIDs: stills, magicMaskDirs: masks))
    }

    private static let maskPattern = try! NSRegularExpression(
        pattern: "/(?:Users|Volumes)/[^\\x00-\\x1f]*?/Magic Mask(?=[\\x00-\\x1f/]|$)")

    /// Finds `.../Magic Mask` folder paths stored verbatim inside a clip blob.
    public static func extractMagicMaskDirs(from blob: [UInt8]) -> Set<String> {
        // Latin-1 maps every byte to one character, so regex offsets map back to bytes 1:1.
        guard let latin = String(bytes: blob, encoding: .isoLatin1) else { return [] }
        let ns = latin as NSString
        var result = Set<String>()
        for m in maskPattern.matches(in: latin, range: NSRange(location: 0, length: ns.length)) {
            let slice = Array(blob[m.range.location..<(m.range.location + m.range.length)])
            if let path = String(bytes: slice, encoding: .utf8) {
                result.insert(path.precomposedStringWithCanonicalMapping)
            }
        }
        return result
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    /// Runs `sql`, calling `each` per row. Returns false if the statement can't be prepared (e.g. missing table).
    private static func query(_ db: OpaquePointer?, _ sql: String, _ each: (OpaquePointer?) -> Void) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { each(stmt) }
        return true
    }
}
