import CryptoKit
import Foundation
import SQLite3

public let lutExtensions: Set<String> = ["cube", "3dl", "dat", "csp", "ilut", "olut"]

public struct LutCopy: Hashable, Sendable {
    public let url: URL
    public let relativePath: String
    public let bytes: Int64
    /// Projects whose database mentions this LUT (by relative path or file name).
    public var usedBy: [String] = []
    public var isSelectable: Bool { usedBy.isEmpty }
}

public struct LutGroup: Identifiable, Sendable {
    public let id: String            // SHA-256 of the content
    public var copies: [LutCopy]
    /// Space that removing all but one copy would free.
    public var wasted: Int64 { copies.isEmpty ? 0 : copies[0].bytes * Int64(copies.count - 1) }
}

/// Byte-identical LUT files under `root`. Hashes only files that share a size with another file.
public func findLutDuplicates(root: URL) -> [LutGroup] {
    let fm = FileManager.default
    guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return [] }
    let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
    var bySize: [Int64: [URL]] = [:]
    for case let f as URL in walker where lutExtensions.contains(f.pathExtension.lowercased()) {
        guard let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true else { continue }
        bySize[Int64(v.fileSize ?? 0), default: []].append(f)
    }
    var byHash: [String: [LutCopy]] = [:]
    for (size, urls) in bySize where urls.count > 1 && size > 0 {
        for u in urls {
            guard let h = sha256(u) else { continue }
            let full = u.standardizedFileURL.resolvingSymlinksInPath().path
            let rel = full.hasPrefix(rootPath + "/") ? String(full.dropFirst(rootPath.count + 1)) : u.lastPathComponent
            byHash[h, default: []].append(LutCopy(url: u, relativePath: rel.precomposedStringWithCanonicalMapping, bytes: size))
        }
    }
    return byHash.filter { $0.value.count > 1 }
        .map { LutGroup(id: $0.key, copies: $0.value.sorted { $0.relativePath < $1.relativePath }) }
        .sorted { $0.wasted != $1.wasted ? $0.wasted > $1.wasted : $0.id < $1.id }
}

private func sha256(_ url: URL) -> String? {
    guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? h.close() }
    var hasher = SHA256()
    while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private let lutRefPattern = try! NSRegularExpression(
    pattern: "[^\\x00-\\x1f]{0,300}?\\.(?:cube|3dl|dat|csp|ilut|olut)(?![A-Za-z0-9])", options: [.caseInsensitive])

/// Every LUT-looking string in every project database (all tables, raw and zstd-decompressed values),
/// lowercased → names of projects that mention it.
public func lutReferences(projects: [Project]) -> [String: Set<String>] {
    var refs: [String: Set<String>] = [:]
    for p in projects {
        _ = ProjectReader.withReadOnlyDB(p.dbURL) { db -> Result<Void, ProjectReadError> in
            var tables: [String] = []
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table'", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW { tables.append(String(cString: sqlite3_column_text(stmt, 0))) }
            }
            sqlite3_finalize(stmt)
            for t in tables {
                var s: OpaquePointer?
                guard sqlite3_prepare_v2(db, "SELECT * FROM \"\(t)\"", -1, &s, nil) == SQLITE_OK else { continue }
                while sqlite3_step(s) == SQLITE_ROW {
                    for c in 0..<sqlite3_column_count(s) {
                        let type = sqlite3_column_type(s, c)
                        guard type == SQLITE_BLOB || type == SQLITE_TEXT, let ptr = sqlite3_column_blob(s, c) else { continue }
                        let bytes = Array(UnsafeRawBufferPointer(start: ptr, count: Int(sqlite3_column_bytes(s, c))))
                        guard bytes.count > 4 else { continue }
                        for chunk in [bytes, Zstd.decompressEmbeddedFrame(bytes) ?? []] where !chunk.isEmpty {
                            for ref in lutStrings(chunk) { refs[ref, default: []].insert(p.name) }
                        }
                    }
                }
                sqlite3_finalize(s)
            }
            return .success(())
        }
    }
    return refs
}

private func lutStrings(_ bytes: [UInt8]) -> [String] {
    guard let latin = String(bytes: bytes, encoding: .isoLatin1) else { return [] }
    return lutRefPattern.matches(in: latin, range: NSRange(location: 0, length: (latin as NSString).length)).compactMap { m in
        let slice = Array(bytes[m.range.location..<(m.range.location + m.range.length)])
        return (String(bytes: slice, encoding: .utf8) ?? String(bytes: slice, encoding: .isoLatin1))?
            .precomposedStringWithCanonicalMapping.lowercased()
    }
}

/// LUTs that DCTLs depend on. DCTL tools load LUTs by path (often from hidden `.resources` folders and from
/// encrypted `.dctle` files we can't read), so: every LUT inside a folder that holds a `.dctl`/`.dctle` counts as used
/// by that DCTL pack, plus every LUT path written in a readable `.dctl` source.
public func dctlReferences(root: URL) -> [String: Set<String>] {
    let fm = FileManager.default
    guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
    let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
    func rel(_ u: URL) -> String {
        let full = u.standardizedFileURL.resolvingSymlinksInPath().path
        return (full.hasPrefix(rootPath + "/") ? String(full.dropFirst(rootPath.count + 1)) : u.lastPathComponent)
            .precomposedStringWithCanonicalMapping.lowercased()
    }
    var refs: [String: Set<String>] = [:]
    var dctlDirs = Set<URL>()
    for case let f as URL in walker {
        let ext = f.pathExtension.lowercased()
        guard ext == "dctl" || ext == "dctle" else { continue }
        dctlDirs.insert(f.deletingLastPathComponent().standardizedFileURL)
        if ext == "dctl", let data = try? Data(contentsOf: f) {
            for s in lutStrings(Array(data)) { refs[s, default: []].insert("DCTL · \(f.lastPathComponent)") }
        }
    }
    for dir in dctlDirs {
        guard let inner = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
        for case let f as URL in inner where lutExtensions.contains(f.pathExtension.lowercased()) {
            refs[rel(f), default: []].insert("DCTL · \(dir.lastPathComponent)")
        }
    }
    return refs
}

/// Marks each copy with the projects that reference it. Conservative: a match on the file name alone counts.
public func markUsage(_ groups: [LutGroup], refs: [String: Set<String>]) -> [LutGroup] {
    groups.map { g in
        var g = g
        g.copies = g.copies.map { c in
            var c = c
            let rel = c.relativePath.lowercased()
            let name = (rel as NSString).lastPathComponent
            var users = Set<String>()
            for (ref, projects) in refs where ref == rel || ref.hasSuffix("/" + rel) || ref.hasSuffix(name) {
                users.formUnion(projects)
            }
            c.usedBy = users.sorted()
            return c
        }
        return g
    }
}

public extension LutCopy {
    var storageItem: StorageItem {
        StorageItem(category: .lut, url: url, bytes: bytes, projectIDs: [], match: .unlinked, label: relativePath)
    }
}
