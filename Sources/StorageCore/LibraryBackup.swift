import Foundation

/// Copies every project library (`<root>/Resolve Projects`) into a dated, versioned folder before a cleanup,
/// and keeps only the newest N such folders. Only folders carrying our marker file are ever rotated.
public enum LibraryBackup {
    public static let markerName = ".davinci-storage-backup"

    public struct Marker: Codable, Equatable, Sendable {
        public let date: Date
        public let version: String
        public let libraries: [String]
    }

    public enum BackupError: Error, Equatable {
        case targetInsideLibrary
        case noLibraries
        case copyFailed(String)
        case verificationFailed(String)

        public var message: String {
            switch self {
            case .targetInsideLibrary: "Папка бекапів лежить усередині бази проєктів — вибери іншу в налаштуваннях."
            case .noLibraries: "Не знайдено жодної доступної бази проєктів для бекапу."
            case .copyFailed(let s): "Не вдалося скопіювати базу: \(s)"
            case .verificationFailed(let s): "Копія бази не збігається з оригіналом: \(s)"
            }
        }
    }

    /// Version of the installed DaVinci Resolve (free or Studio), or «невідома версія».
    public static func resolveVersion(appsDir: URL = URL(fileURLWithPath: "/Applications")) -> String {
        let candidates = ["DaVinci Resolve/DaVinci Resolve.app", "DaVinci Resolve Studio/DaVinci Resolve Studio.app",
                          "DaVinci Resolve.app", "DaVinci Resolve Studio.app"]
        for c in candidates {
            let plist = appsDir.appendingPathComponent(c).appendingPathComponent("Contents/Info.plist")
            if let dict = NSDictionary(contentsOf: plist), let v = dict["CFBundleShortVersionString"] as? String, !v.isEmpty {
                return v
            }
        }
        return "невідома версія"
    }

    /// "2026-11-11 20-05 · DaVinci Resolve 21.2.0"
    public static func folderName(date: Date, version: String, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH-mm"
        return "\(f.string(from: date)) · DaVinci Resolve \(version)"
    }

    @discardableResult
    public static func create(libraries: [Library], in root: URL, date: Date, version: String,
                              copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
                              trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })
    throws -> URL {
        let fm = FileManager.default
        let target = canonical(root)
        // A backup connected back into Resolve as a library must not be backed up again (backups of backups).
        let libraries = libraries.filter { lib in
            let r = canonical(lib.root)
            return !(r == target || r.hasPrefix(target + "/"))
        }
        guard !libraries.isEmpty else { throw BackupError.noLibraries }
        for lib in libraries {
            let rp = canonical(lib.root.appendingPathComponent("Resolve Projects"))
            if target == rp || target.hasPrefix(rp + "/") { throw BackupError.targetInsideLibrary }
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let base = folderName(date: date, version: version)
        var out = root.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: out.path) {
            out = root.appendingPathComponent("\(base) (\(n))", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: out, withIntermediateDirectories: true)

        do {
            var usedNames = Set<String>()
            for lib in libraries {
                var name = lib.name.isEmpty ? "База" : lib.name
                var k = 2
                while !usedNames.insert(name).inserted { name = "\(lib.name) (\(k))"; k += 1 }
                let src = lib.root.appendingPathComponent("Resolve Projects", isDirectory: true)
                guard fm.fileExists(atPath: src.path) else { throw BackupError.copyFailed("\(lib.name): немає папки Resolve Projects") }
                let dst = out.appendingPathComponent(name, isDirectory: true).appendingPathComponent("Resolve Projects", isDirectory: true)
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                do { try copy(src, dst) } catch { throw BackupError.copyFailed("\(lib.name): \(error.localizedDescription)") }
                let (sc, ss) = fileStats(src), (dc, ds) = fileStats(dst)
                guard sc == dc, ss == ds else {
                    throw BackupError.verificationFailed("\(lib.name): \(dc)/\(sc) файлів, \(ds)/\(ss) байтів")
                }
            }
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(Marker(date: date, version: version, libraries: libraries.map(\.name)))
                .write(to: out.appendingPathComponent(markerName))
        } catch {
            try? trash(out)
            throw (error as? BackupError) ?? BackupError.copyFailed(error.localizedDescription)
        }
        return out
    }

    /// Moves all but the newest `keep` marked backup folders to the Trash. Returns what was removed.
    @discardableResult
    public static func rotate(in root: URL, keep: Int, liveLibraries: [Library] = [],
                              trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> [URL] {
        let live = liveLibraries.map { canonical($0.root) }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let marked: [(URL, Date)] = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(markerName)),
                  let m = try? dec.decode(Marker.self, from: data) else { return nil }
            let d = canonical(dir)
            // A backup that Resolve currently uses as a library is never rotated (nor counted).
            if live.contains(where: { $0 == d || $0.hasPrefix(d + "/") }) { return nil }
            return (dir, m.date)
        }
        let ordered = marked.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lastPathComponent > $1.0.lastPathComponent }
        var removed: [URL] = []
        for (dir, _) in ordered.dropFirst(max(0, keep)) {
            if (try? trash(dir)) != nil { removed.append(dir) }
        }
        return removed
    }

    /// Number of regular files and their total logical size.
    static func fileStats(_ url: URL) -> (Int, Int64) {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return (0, 0) }
        var count = 0, bytes: Int64 = 0
        for case let f as URL in walker {
            guard let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(v.fileSize ?? 0)
        }
        return (count, bytes)
    }

    static func canonical(_ url: URL) -> String {
        normalizedPath(url.resolvingSymlinksInPath()).lowercased()
    }
}
