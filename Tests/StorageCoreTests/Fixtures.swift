import Foundation
import SQLite3

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("dvs-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes `bytes` zero bytes into a new file, creating parent folders.
@discardableResult
func makeFile(_ url: URL, bytes: Int = 4096) -> URL {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data(count: bytes))
    return url
}

/// Minimal stand-in for a Resolve Project.db with the tables the reader uses.
func makeProjectDB(at url: URL, id: String, name: String, lastMod: Int64,
                   stillIDs: [String] = [], clipBlobs: [[UInt8]] = []) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw NSError(domain: "fixture", code: 1) }
    defer { sqlite3_close(db) }
    func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }
    exec("CREATE TABLE SM_Project (SM_Project_id uuid, ProjectName varchar, LastModTimeInSecs bigint)")
    exec("CREATE TABLE \"Gallery::GyStill\" (\"Gallery::GyStill_id\" uuid)")
    exec("CREATE TABLE BtVideoInfo (Clip blob)")
    exec("INSERT INTO SM_Project VALUES ('\(id)', '\(name)', \(lastMod))")
    for s in stillIDs { exec("INSERT INTO \"Gallery::GyStill\" VALUES ('\(s)')") }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for blob in clipBlobs {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO BtVideoInfo VALUES (?)", -1, &stmt, nil)
        blob.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(blob.count), transient) }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }
}

/// Blob shaped like Resolve's BtVideoInfo.Clip: binary header, length byte, path, filename.
func clipBlob(dir: String, file: String = "shot_01.mov") -> [UInt8] {
    [0, 0, 0, 2, 0x28, 0xB5, 0x2F, 0xFD, 0x0A, 0x37] + Array(dir.utf8) + [0x12, 0x1B] + Array(file.utf8)
}
