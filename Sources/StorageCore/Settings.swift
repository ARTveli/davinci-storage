import Foundation

/// User preferences, persisted in UserDefaults.
public struct StorageSettings: Equatable, Sendable {
    public var backupFolder: URL
    public var keepLibraryBackups: Int
    public var keepProjectBackups: Int
    public var protectedProjectIDs: Set<String>

    enum Key {
        static let backupFolder = "backupFolder"
        static let keepLibraryBackups = "keepLibraryBackups"
        static let keepProjectBackups = "keepProjectBackups"
        static let protectedProjectIDs = "protectedProjectIDs"
    }

    public static func load(_ d: UserDefaults = .standard,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> StorageSettings {
        let folder = d.string(forKey: Key.backupFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent("DAVINCI_DATA_BASE/_BACKUPS", isDirectory: true)
        let keepLib = d.object(forKey: Key.keepLibraryBackups) as? Int ?? 10
        let keepProj = d.object(forKey: Key.keepProjectBackups) as? Int ?? 3
        let protected = Set((d.stringArray(forKey: Key.protectedProjectIDs) ?? []).map { $0.lowercased() })
        return StorageSettings(backupFolder: folder, keepLibraryBackups: max(1, keepLib),
                               keepProjectBackups: max(1, keepProj), protectedProjectIDs: protected)
    }

    public func save(_ d: UserDefaults = .standard) {
        d.set(backupFolder.path, forKey: Key.backupFolder)
        d.set(keepLibraryBackups, forKey: Key.keepLibraryBackups)
        d.set(keepProjectBackups, forKey: Key.keepProjectBackups)
        d.set(protectedProjectIDs.sorted(), forKey: Key.protectedProjectIDs)
    }
}
