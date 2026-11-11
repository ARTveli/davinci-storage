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
        guard let users = try? fm.contentsOfDirectory(at: usersDir(library), includingPropertiesForKeys: nil) else { return [] }
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

    /// False when the library's `Resolve Projects/Users` folder can't be listed (unmounted volume, no permission…).
    public static func isReachable(_ library: Library) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: usersDir(library).path)) != nil
    }

    private static func usersDir(_ library: Library) -> URL {
        library.root.appendingPathComponent("Resolve Projects/Users", isDirectory: true)
    }

    public static func read(dbURL: URL, library: String) -> Result<Project, ProjectReadError> {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return .failure(.open("file not found")) }
        return withReadOnlyDB(dbURL) { db in
            var row: (String, String, Int64?)?
            if case .error(let e) = query(db, "SELECT SM_Project_id, ProjectName, LastModTimeInSecs FROM SM_Project LIMIT 1", { stmt in
                let mod: Int64? = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2)
                row = (text(stmt, 0), text(stmt, 1), mod)
            }) { return .failure(.query(e)) }
            guard let (id, name, lastMod) = row, !id.isEmpty else { return .failure(.noProjectRow) }

            var stills = Set<String>()
            if case .error(let e) = query(db, "SELECT \"Gallery::GyStill_id\" FROM \"Gallery::GyStill\"", { stmt in
                stills.insert(text(stmt, 0).lowercased())
            }) { return .failure(.query(e)) }

            var masks = Set<String>()
            if case .error(let e) = query(db, "SELECT Clip FROM BtVideoInfo", { stmt in
                guard let ptr = sqlite3_column_blob(stmt, 0) else { return }
                let bytes = Array(UnsafeRawBufferPointer(start: ptr, count: Int(sqlite3_column_bytes(stmt, 0))))
                masks.formUnion(extractMagicMaskDirs(from: bytes))
            }) { return .failure(.query(e)) }

            var folders = WorkingFolders()
            if case .error(let e) = query(db, "SELECT FieldsBlob FROM SM_Config", { stmt in
                guard let ptr = sqlite3_column_blob(stmt, 0) else { return }
                let bytes = Array(UnsafeRawBufferPointer(start: ptr, count: Int(sqlite3_column_bytes(stmt, 0))))
                let f = extractWorkingFolders(from: bytes)
                folders.magicMaskRoots.formUnion(f.magicMaskRoots)
                folders.cacheRoots.formUnion(f.cacheRoots)
                folders.proxyRoots.formUnion(f.proxyRoots)
            }) { return .failure(.query(e)) }
            // Resolve writes Magic Mask files to "<configured folder>/Magic Mask".
            masks.formUnion(folders.magicMaskRoots.map { normalizedPath(URL(fileURLWithPath: $0).appendingPathComponent("Magic Mask")) })

            let modified = lastMod.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? fileModificationDate(dbURL)
            return .success(Project(id: id.lowercased(), name: name, library: library, dbURL: dbURL,
                                    lastModified: modified, stillIDs: stills, magicMaskDirs: masks,
                                    cacheRoots: folders.cacheRoots, proxyRoots: folders.proxyRoots))
        }
    }

    /// User-level galleries (PowerGrades etc.): `SM_User_id`s and their still IDs from every `User.db` of a library.
    public static func readUserGalleries(in library: Library) -> Result<UserGalleries, ProjectReadError> {
        guard let users = try? FileManager.default.contentsOfDirectory(at: usersDir(library), includingPropertiesForKeys: nil) else {
            return .failure(.open("library not reachable"))
        }
        var result = UserGalleries.empty
        for user in users {
            let db = user.appendingPathComponent("User.db")
            guard FileManager.default.fileExists(atPath: db.path) else { continue }
            let r: Result<UserGalleries, ProjectReadError> = withReadOnlyDB(db) { h in
                var g = UserGalleries.empty
                if case .error(let e) = query(h, "SELECT SM_User_id FROM SM_User", { g.userIDs.insert(text($0, 0).lowercased()) }) {
                    return .failure(.query(e))
                }
                if case .error(let e) = query(h, "SELECT \"Gallery::GyStill_id\" FROM \"Gallery::GyStill\"", { g.stillIDs.insert(text($0, 0).lowercased()) }) {
                    return .failure(.query(e))
                }
                return .success(g)
            }
            switch r {
            case .success(let g):
                result.userIDs.formUnion(g.userIDs)
                result.stillIDs.formUnion(g.stillIDs)
            case .failure(let e):
                return .failure(e)
            }
        }
        return .success(result)
    }

    private static let maskPattern = try! NSRegularExpression(
        // Starts at the LAST /Users|/Volumes before "/Magic Mask" so an adjacent earlier path can't be swallowed.
        pattern: "/(?:Users|Volumes)/(?:(?!/(?:Users|Volumes)/)[^\\x00-\\x1f])*?/Magic Mask")

    /// Finds `.../Magic Mask` folder paths in a clip blob, both in its raw bytes and inside its zstd frame.
    public static func extractMagicMaskDirs(from blob: [UInt8]) -> Set<String> {
        var result = matchMaskPaths(blob)
        if let plain = Zstd.decompressEmbeddedFrame(blob) { result.formUnion(matchMaskPaths(plain)) }
        return result
    }

    /// Working folders from an SM_Config.FieldsBlob (protobuf, usually inside a zstd frame).
    /// Fields: 124 = Magic Mask location, 39 = cache files location, 40 = proxy generation location.
    public static func extractWorkingFolders(from blob: [UInt8]) -> WorkingFolders {
        var f = WorkingFolders()
        for bytes in [blob, Zstd.decompressEmbeddedFrame(blob) ?? []] where !bytes.isEmpty {
            f.magicMaskRoots.formUnion(stringFields(bytes, tag: [0xE2, 0x07]))
            f.cacheRoots.formUnion(stringFields(bytes, tag: [0xBA, 0x02]))
            f.proxyRoots.formUnion(stringFields(bytes, tag: [0xC2, 0x02]))
        }
        return f
    }

    /// Length-delimited string values following `tag` that look like absolute paths.
    private static func stringFields(_ b: [UInt8], tag: [UInt8]) -> Set<String> {
        var result = Set<String>()
        var i = 0
        while i + tag.count < b.count {
            defer { i += 1 }
            guard b[i] == tag[0], Array(b[i..<(i + tag.count)]) == tag else { continue }
            var j = i + tag.count, len = 0, shift = 0
            while j < b.count, shift <= 14 {               // varint length, at most 3 bytes
                len |= Int(b[j] & 0x7F) << shift
                j += 1
                if b[j - 1] & 0x80 == 0 { break }
                shift += 7
            }
            guard len > 1, j + len <= b.count, b[j] == UInt8(ascii: "/"),
                  let s = String(bytes: b[j..<(j + len)], encoding: .utf8), !s.contains("\0") else { continue }
            result.insert(normalizedPath(URL(fileURLWithPath: s)))
        }
        return result
    }

    private static func matchMaskPaths(_ bytes: [UInt8]) -> Set<String> {
        // Latin-1 maps every byte to one character, so regex offsets map back to bytes 1:1.
        guard let latin = String(bytes: bytes, encoding: .isoLatin1) else { return [] }
        var result = Set<String>()
        for m in maskPattern.matches(in: latin, range: NSRange(location: 0, length: (latin as NSString).length)) {
            let slice = Array(bytes[m.range.location..<(m.range.location + m.range.length)])
            if let path = String(bytes: slice, encoding: .utf8) {
                result.insert(path.precomposedStringWithCanonicalMapping)
            }
        }
        return result
    }

    private static func fileModificationDate(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
    }

    private static func withReadOnlyDB<T>(_ url: URL, _ body: (OpaquePointer?) -> Result<T, ProjectReadError>) -> Result<T, ProjectReadError> {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            return .failure(.open(msg))
        }
        defer { sqlite3_close(db) }
        return body(db)
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    private enum QueryResult { case ok, noTable, error(String) }

    /// Runs `sql`, calling `each` per row. A missing table is not an error; any other failure
    /// (including one while stepping, e.g. BUSY/CORRUPT) is, so a half-read project never counts as read.
    private static func query(_ db: OpaquePointer?, _ sql: String, _ each: (OpaquePointer?) -> Void) -> QueryResult {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            return msg.contains("no such table") ? .noTable : .error(msg)
        }
        defer { sqlite3_finalize(stmt) }
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW {
            each(stmt)
            rc = sqlite3_step(stmt)
        }
        return rc == SQLITE_DONE ? .ok : .error(String(cString: sqlite3_errmsg(db)))
    }
}
