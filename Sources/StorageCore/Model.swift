import Foundation

public enum Category: String, CaseIterable, Sendable {
    case cache, backups, stills, magicMask, proxy, service, lut
}

public enum MatchKind: Sendable {
    case uuidFolder, dbPath, stillID, byName, unlinked
}

public struct Library: Hashable, Sendable {
    public let name: String
    public let root: URL
    public init(name: String, root: URL) {
        self.name = name
        self.root = root
    }
}

public struct Project: Hashable, Sendable {
    public let id: String
    public let name: String
    public let library: String
    public let dbURL: URL
    public let lastModified: Date
    public let stillIDs: Set<String>
    public let magicMaskDirs: Set<String>
    /// Working folders from Project Settings (cache files / proxy generation location), normalized paths.
    public var cacheRoots: Set<String>
    public var proxyRoots: Set<String>
    /// Magic Mask folders as set in Project Settings (without the "/Magic Mask" suffix).
    public var configuredMaskRoots: Set<String> = []

    public init(id: String, name: String, library: String, dbURL: URL, lastModified: Date,
                stillIDs: Set<String>, magicMaskDirs: Set<String>,
                cacheRoots: Set<String> = [], proxyRoots: Set<String> = []) {
        self.cacheRoots = cacheRoots
        self.proxyRoots = proxyRoots
        self.id = id
        self.name = name
        self.library = library
        self.dbURL = dbURL
        self.lastModified = lastModified
        self.stillIDs = stillIDs
        self.magicMaskDirs = magicMaskDirs
    }
}

public struct StorageItem: Hashable, Sendable {
    public let category: Category
    public let url: URL
    public let bytes: Int64
    public let projectIDs: [String]
    public let match: MatchKind
    public let label: String

    public init(category: Category, url: URL, bytes: Int64, projectIDs: [String], match: MatchKind, label: String) {
        self.category = category
        self.url = url
        self.bytes = bytes
        self.projectIDs = projectIDs
        self.match = match
        self.label = label
    }
}

public struct ResolveConfig: Sendable {
    public let libraries: [Library]
    public let backupRoot: URL?
    /// Non-disk (e.g. PostgreSQL) libraries that are not scanned.
    public let skippedLibraries: [String]
    public init(libraries: [Library], backupRoot: URL?, skippedLibraries: [String] = []) {
        self.libraries = libraries
        self.backupRoot = backupRoot
        self.skippedLibraries = skippedLibraries
    }
}

/// Folders configured in a project's settings (SM_Config).
public struct WorkingFolders: Sendable, Equatable {
    public var magicMaskRoots: Set<String> = []
    public var cacheRoots: Set<String> = []
    public var proxyRoots: Set<String> = []
    public init() {}
}

/// User-level gallery data (PowerGrades and other user albums) — never a project leftover.
public struct UserGalleries: Sendable, Equatable {
    public var userIDs: Set<String>
    public var stillIDs: Set<String>
    public init(userIDs: Set<String>, stillIDs: Set<String>) {
        self.userIDs = userIDs
        self.stillIDs = stillIDs
    }
    public static let empty = UserGalleries(userIDs: [], stillIDs: [])
}

/// Canonical form for comparing paths (standardized, NFC — Cyrillic names may be NFD on disk).
public func normalizedPath(_ url: URL) -> String {
    url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
}
