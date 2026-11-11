import Foundation

public enum CleanerRefusal: Error, Equatable {
    case outsideAllowedRoots, isRoot, insideLibrary, notFound

    public var message: String {
        switch self {
        case .outsideAllowedRoots: "шлях поза папками DaVinci, які програма має право чистити"
        case .isRoot: "це коренева папка — її не можна видаляти цілком"
        case .insideLibrary: "шлях належить базі проєктів DaVinci"
        case .notFound: "файл або папку вже не знайдено"
        }
    }
}

public struct CleanResult: Sendable {
    public var trashed: [URL] = []
    public var failed: [(url: URL, reason: String)] = []
}

/// Moves items to the Trash, but only inside known DaVinci locations and never inside a project library.
public struct Cleaner: Sendable {
    let allowedRoots: [String]
    let allowedItems: Set<String>
    let libraryRoots: [String]
    let trash: @Sendable (URL) throws -> Void

    public init(allowedRoots: [URL], allowedItems: [URL], libraryRoots: [URL],
                trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.allowedRoots = allowedRoots.map(Cleaner.canonical)
        self.allowedItems = Set(allowedItems.map(Cleaner.canonical))
        self.libraryRoots = libraryRoots.map(Cleaner.canonical)
        self.trash = trash
    }

    static func canonical(_ url: URL) -> String {
        normalizedPath(url.resolvingSymlinksInPath())
    }

    public func validate(_ url: URL) -> CleanerRefusal? {
        guard FileManager.default.fileExists(atPath: url.path) else { return .notFound }
        let path = Cleaner.canonical(url)
        if allowedRoots.contains(path) { return .isRoot }
        if libraryRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) {
            return .insideLibrary
        }
        if allowedItems.contains(path) { return nil }
        if allowedRoots.contains(where: { path.hasPrefix($0 + "/") }) { return nil }
        return .outsideAllowedRoots
    }

    public func clean(_ urls: [URL]) -> CleanResult {
        var result = CleanResult()
        for url in urls {
            if let refusal = validate(url) {
                result.failed.append((url, refusal.message))
                continue
            }
            do {
                try trash(url)
                result.trashed.append(url)
            } catch {
                result.failed.append((url, error.localizedDescription))
            }
        }
        return result
    }
}

public extension ScanResult {
    /// Cleaner allowed to touch every scanned location, the service caches and the Magic Mask folders projects use.
    func makeCleaner() -> Cleaner {
        let l = locations
        let roots = allCacheRoots(l, projects) + [l.backupRoot].compactMap { $0 } + [l.galleryProjectRoot, l.galleryLegacyRoot]
            + l.magicMaskRoots + allProxyRoots(l, projects) + [l.lutRoot].compactMap { $0 }
        let crashFiles = l.crashReportsDir.map { dir in
            ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.localizedCaseInsensitiveContains("Resolve") }
        } ?? []
        let items = l.serviceItems.map(\.url) + crashFiles + projects.flatMap { $0.magicMaskDirs.map { URL(fileURLWithPath: $0) } }
        return Cleaner(allowedRoots: roots, allowedItems: items, libraryRoots: libraryRoots)
    }
}
