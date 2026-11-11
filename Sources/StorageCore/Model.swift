import Foundation

public enum Category: String, CaseIterable, Sendable {
    case cache, backups, stills, magicMask, proxy, service
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

    public init(id: String, name: String, library: String, dbURL: URL, lastModified: Date,
                stillIDs: Set<String>, magicMaskDirs: Set<String>) {
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
    public init(libraries: [Library], backupRoot: URL?) {
        self.libraries = libraries
        self.backupRoot = backupRoot
    }
}

/// Canonical form for comparing paths (standardized, NFC — Cyrillic names may be NFD on disk).
public func normalizedPath(_ url: URL) -> String {
    url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
}
