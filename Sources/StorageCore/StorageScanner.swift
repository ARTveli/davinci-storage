import Foundation

/// Walks every location and turns what it finds into `StorageItem`s linked to projects where possible.
/// Zero-byte items are skipped (empty folders are noise, freeing them gains nothing).
public func scanStorage(_ loc: Locations, projects: [Project]) -> [StorageItem] {
    let byID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var items: [StorageItem] = []
    func add(_ category: Category, _ url: URL, _ ids: [String], _ match: MatchKind, _ label: String) {
        let bytes = allocatedSize(of: url)
        guard bytes > 0 else { return }
        items.append(StorageItem(category: category, url: url, bytes: bytes, projectIDs: ids, match: match, label: label))
    }

    // Cache + backups: folders named by project UUID.
    let uuidRoots: [(Category, URL)] = loc.cacheRoots.map { (.cache, $0) } + (loc.backupRoot.map { [(.backups, $0)] } ?? [])
    for (category, root) in uuidRoots {
        for dir in subdirectories(of: root) {
            guard let id = uuidName(dir) else { continue }
            add(category, dir, [id], .uuidFolder, byID[id]?.name ?? id)
        }
    }

    // Stills, per-project gallery folders (`<UUID>/Info.txt`).
    for dir in subdirectories(of: loc.galleryProjectRoot) {
        guard let id = uuidName(dir) else { continue }
        add(.stills, dir, [id], .uuidFolder, byID[id]?.name ?? infoProjectName(dir) ?? id)
    }

    // Stills, legacy shared gallery (`<StillUUID>.dpx`).
    var stillOwner: [String: Project] = [:]
    for p in projects { for s in p.stillIDs { stillOwner[s] = p } }
    for file in files(in: loc.galleryLegacyRoot) where file.pathExtension.lowercased() == "dpx" {
        let stem = file.deletingPathExtension().lastPathComponent.lowercased()
        if let owner = stillOwner[stem] {
            add(.stills, file, [owner.id], .stillID, "Стіл \(owner.name)")
        } else {
            add(.stills, file, [], .unlinked, file.lastPathComponent)
        }
    }

    // Magic Mask: first the folders projects actually reference…
    var maskUsers: [String: [String]] = [:]
    for p in projects { for d in p.magicMaskDirs { maskUsers[d, default: []].append(p.id) } }
    let claimed = Set(maskUsers.keys)
    for dir in maskUsers.keys.sorted() {
        let ids = maskUsers[dir]!
        add(.magicMask, URL(fileURLWithPath: dir, isDirectory: true), ids, .dbPath, ids.compactMap { byID[$0]?.name }.joined(separator: ", "))
    }
    // …then whatever else sits in the Magic Mask roots.
    for root in loc.magicMaskRoots {
        for dir in subdirectories(of: root) {
            let path = normalizedPath(dir)
            if claimed.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { continue }
            addByName(.magicMask, dir)
        }
    }

    for root in loc.proxyRoots {
        for dir in subdirectories(of: root) { addByName(.proxy, dir) }
    }

    for service in loc.serviceItems {
        add(.service, service.url, [], .unlinked, service.label)
    }
    return items

    func addByName(_ category: Category, _ dir: URL) {
        let name = dir.lastPathComponent.precomposedStringWithCanonicalMapping
        if let p = projects.first(where: { $0.name.precomposedStringWithCanonicalMapping.caseInsensitiveCompare(name) == .orderedSame }) {
            add(category, dir, [p.id], .byName, name)
        } else {
            add(category, dir, [], .unlinked, name)
        }
    }
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
