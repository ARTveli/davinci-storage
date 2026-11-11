import Foundation

public struct ServiceLocation: Hashable, Sendable {
    public let label: String
    public let url: URL
    public init(label: String, url: URL) {
        self.label = label
        self.url = url
    }
}

/// Every folder the scanner looks at.
public struct Locations: Sendable {
    public var cacheRoots: [URL]
    public var backupRoot: URL?
    public var galleryProjectRoot: URL
    public var galleryLegacyRoot: URL
    public var magicMaskRoots: [URL]
    public var proxyRoots: [URL]
    public var serviceItems: [ServiceLocation]
    /// Resolve's LUT library (for duplicate detection).
    public var lutRoot: URL?
    /// macOS crash reports; files whose name contains "Resolve" are listed.
    public var crashReportsDir: URL?

    public init(cacheRoots: [URL], backupRoot: URL?, galleryProjectRoot: URL, galleryLegacyRoot: URL,
                magicMaskRoots: [URL], proxyRoots: [URL], serviceItems: [ServiceLocation],
                lutRoot: URL? = nil, crashReportsDir: URL? = nil) {
        self.lutRoot = lutRoot
        self.crashReportsDir = crashReportsDir
        self.cacheRoots = cacheRoots
        self.backupRoot = backupRoot
        self.galleryProjectRoot = galleryProjectRoot
        self.galleryLegacyRoot = galleryLegacyRoot
        self.magicMaskRoots = magicMaskRoots
        self.proxyRoots = proxyRoots
        self.serviceItems = serviceItems
    }

    public static let systemResolve = URL(fileURLWithPath: "/Library/Application Support/Blackmagic Design/DaVinci Resolve", isDirectory: true)

    /// Resolve's default locations on this Mac (verified 2026-11-11) plus the backup folder from preferences.
    public static func real(home: URL, config: ResolveConfig) -> Locations {
        let s = systemResolve
        let u = home.appendingPathComponent("Library/Application Support/Blackmagic Design/DaVinci Resolve", isDirectory: true)
        let movies = home.appendingPathComponent("Movies", isDirectory: true)
        return Locations(
            cacheRoots: [movies.appendingPathComponent("CacheClip"), s.appendingPathComponent("CacheClip")],
            backupRoot: config.backupRoot ?? movies.appendingPathComponent("Resolve Project Backups"),
            galleryProjectRoot: movies.appendingPathComponent(".gallery"),
            galleryLegacyRoot: s.appendingPathComponent(".gallery"),
            magicMaskRoots: [home.appendingPathComponent("MAGIC_MASK_2_DAVINCI"),
                             home.appendingPathComponent("DaVinci Resolve Media")],
            proxyRoots: [s.appendingPathComponent("ProxyMedia"),
                         movies.appendingPathComponent("ProxyMedia"),
                         movies.appendingPathComponent("CacheClip/OptimizedMedia"),
                         movies.appendingPathComponent("CacheClip/ProxyMedia")],
            serviceItems: [
                ServiceLocation(label: "LUT-кеш (.LUT)", url: u.appendingPathComponent(".LUT")),
                ServiceLocation(label: "Кеш програми",
                                url: home.appendingPathComponent("Library/Caches/com.blackmagic-design.DaVinciResolve")),
                ServiceLocation(label: "Логи DaVinci", url: u.appendingPathComponent("logs")),
            ],
            lutRoot: s.appendingPathComponent("LUT"),
            crashReportsDir: home.appendingPathComponent("Library/Logs/DiagnosticReports"))
    }
}
