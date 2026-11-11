import Foundation

/// Walks every location and turns what it finds into `StorageItem`s linked to projects where possible.
/// Zero-byte items are skipped (empty folders are noise, freeing them gains nothing).
public func scanStorage(_ loc: Locations, projects: [Project], user: UserGalleries = .empty) -> [StorageItem] {
    let byID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var items: [StorageItem] = []
    func add(_ category: Category, _ url: URL, _ ids: [String], _ match: MatchKind, _ label: String) {
        let bytes = allocatedSize(of: url)
        guard bytes > 0 else { return }
        items.append(StorageItem(category: category, url: url, bytes: bytes, projectIDs: ids, match: match, label: label))
    }

    // Cache + backups: folders named by project UUID.
    let uuidRoots: [(Category, URL)] = allCacheRoots(loc, projects).map { (.cache, $0) } + (loc.backupRoot.map { [(.backups, $0)] } ?? [])
    for (category, root) in uuidRoots {
        for dir in subdirectories(of: root) {
            guard let id = uuidName(dir) else { continue }
            add(category, dir, [id], .uuidFolder, byID[id]?.name ?? id)
        }
    }

    // Stills, per-project gallery folders (`<UUID>/Info.txt`). User-level galleries (PowerGrades) share this
    // root under the user's ID — those, and any folder that doesn't say which project it belongs to, are skipped.
    for dir in subdirectories(of: loc.galleryProjectRoot) {
        guard let id = uuidName(dir), !user.userIDs.contains(id) else { continue }
        if let p = byID[id] {
            add(.stills, dir, [id], .uuidFolder, p.name)
        } else if let name = infoProjectName(dir) {
            add(.stills, dir, [id], .uuidFolder, name)
        }
    }

    // Stills, legacy shared gallery (`<StillUUID>.dpx`).
    var stillOwners: [String: [Project]] = [:]
    for p in projects { for s in p.stillIDs { stillOwners[s, default: []].append(p) } }
    for file in files(in: loc.galleryLegacyRoot) where file.pathExtension.lowercased() == "dpx" {
        let stem = file.deletingPathExtension().lastPathComponent.lowercased()
        if user.stillIDs.contains(stem) { continue }
        if let owners = stillOwners[stem] {
            add(.stills, file, owners.map(\.id), .stillID, "Стіл \(owners.map(\.name).joined(separator: ", "))")
        } else {
            add(.stills, file, [], .unlinked, file.lastPathComponent)
        }
    }

    // Magic Mask: first the folders projects actually reference…
    var maskUsers: [String: [String]] = [:]
    for p in projects { for d in p.magicMaskDirs { maskUsers[d, default: []].append(p.id) } }
    // Compared case-insensitively and through symlinks: APFS is case-insensitive, Resolve may store another spelling.
    let claimed = Set(maskUsers.keys.map { claimKey(URL(fileURLWithPath: $0)) })
    for dir in maskUsers.keys.sorted() {
        let ids = maskUsers[dir]!
        add(.magicMask, URL(fileURLWithPath: dir, isDirectory: true), ids, .dbPath, ids.compactMap { byID[$0]?.name }.joined(separator: ", "))
    }
    // …then whatever else sits in the Magic Mask roots.
    for root in loc.magicMaskRoots {
        for dir in subdirectories(of: root) {
            let path = claimKey(dir)
            if claimed.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { continue }
            addByName(.magicMask, maskTarget(dir), name: dir.lastPathComponent)
        }
    }

    for root in allProxyRoots(loc, projects) {
        for dir in subdirectories(of: root) { addByName(.proxy, dir) }
    }

    for service in loc.serviceItems {
        add(.service, service.url, [], .unlinked, service.label)
    }
    return items

    func addByName(_ category: Category, _ dir: URL, name rawName: String? = nil) {
        let name = (rawName ?? dir.lastPathComponent).precomposedStringWithCanonicalMapping
        if let p = projects.first(where: { $0.name.precomposedStringWithCanonicalMapping.caseInsensitiveCompare(name) == .orderedSame }) {
            add(category, dir, [p.id], .byName, name)
        } else {
            add(category, dir, [], .unlinked, name)
        }
    }
}

/// Default cache roots plus every cache folder configured in a project's settings (deduplicated).
public func allCacheRoots(_ loc: Locations, _ projects: [Project]) -> [URL] {
    merged(loc.cacheRoots, projects.flatMap(\.cacheRoots))
}

public func allProxyRoots(_ loc: Locations, _ projects: [Project]) -> [URL] {
    merged(loc.proxyRoots, projects.flatMap(\.proxyRoots))
}

private func merged(_ base: [URL], _ extra: [String]) -> [URL] {
    var seen = Set(base.map { claimKey($0) })
    var out = base
    for p in extra.sorted() {
        let u = URL(fileURLWithPath: p, isDirectory: true)
        if seen.insert(claimKey(u)).inserted { out.append(u) }
    }
    return out
}

private func claimKey(_ url: URL) -> String {
    normalizedPath(url.resolvingSymlinksInPath()).lowercased()
}

/// For an unclaimed folder in a Magic Mask root: the whole folder when it holds only `Magic Mask`,
/// otherwise just its `Magic Mask` subfolder, so unrelated media next to it is never offered for deletion.
private func maskTarget(_ dir: URL) -> URL {
    let mask = dir.appendingPathComponent("Magic Mask", isDirectory: true)
    guard FileManager.default.fileExists(atPath: mask.path) else { return dir }
    let others = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        .filter { $0 != "Magic Mask" && $0 != ".DS_Store" }
    return others.isEmpty ? dir : mask
}

private func subdirectories(of url: URL) -> [URL] {
    let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.path < $1.path }
}

private func files(in url: URL) -> [URL] {
    let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
    return contents.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
}

private func uuidName(_ url: URL) -> String? {
    UUID(uuidString: url.lastPathComponent) == nil ? nil : url.lastPathComponent.lowercased()
}

private func infoProjectName(_ dir: URL) -> String? {
    guard let text = try? String(contentsOf: dir.appendingPathComponent("Info.txt"), encoding: .utf8) else { return nil }
    for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("Project Name:") {
        return line.dropFirst("Project Name:".count).trimmingCharacters(in: .whitespaces)
    }
    return nil
}
