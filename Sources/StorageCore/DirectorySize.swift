import Foundation

/// On-disk (allocated) size of a file or folder, recursively — like `du`. 0 when missing.
public func allocatedSize(of url: URL) -> Int64 {
    let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isDirectoryKey]
    func fileSize(_ u: URL) -> Int64 {
        guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return 0 }
        return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
    }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
    guard isDir.boolValue else { return fileSize(url) }
    guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
    var total: Int64 = 0
    for case let f as URL in walker { total += fileSize(f) }
    return total
}
