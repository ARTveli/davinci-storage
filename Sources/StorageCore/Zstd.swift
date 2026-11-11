import Darwin
import Foundation

/// Minimal zstd decompression through the system's libzstd (Homebrew), loaded at runtime so the app
/// has no hard dependency on it. When the library is missing, `isAvailable` is false and callers
/// must treat Magic Mask paths as possibly incomplete.
public enum Zstd {
    private typealias Decompress = @convention(c) (UnsafeMutableRawPointer?, Int, UnsafeRawPointer?, Int) -> Int
    private typealias ContentSize = @convention(c) (UnsafeRawPointer?, Int) -> UInt64
    private typealias IsError = @convention(c) (Int) -> UInt32

    private struct Lib: @unchecked Sendable {
        let decompress: Decompress
        let contentSize: ContentSize
        let isError: IsError
    }

    private static let lib: Lib? = {
        let candidates = ["/opt/homebrew/lib/libzstd.1.dylib", "/usr/local/lib/libzstd.1.dylib", "libzstd.1.dylib"]
        for path in candidates {
            guard let h = dlopen(path, RTLD_NOW | RTLD_LOCAL),
                  let d = dlsym(h, "ZSTD_decompress"), let c = dlsym(h, "ZSTD_getFrameContentSize"),
                  let e = dlsym(h, "ZSTD_isError") else { continue }
            return Lib(decompress: unsafeBitCast(d, to: Decompress.self),
                       contentSize: unsafeBitCast(c, to: ContentSize.self),
                       isError: unsafeBitCast(e, to: IsError.self))
        }
        return nil
    }()

    public static var isAvailable: Bool { lib != nil }

    static let magic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]

    /// Decompresses the zstd frame that starts within the first 64 bytes of `blob` (Resolve prefixes a small header).
    public static func decompressEmbeddedFrame(_ blob: [UInt8]) -> [UInt8]? {
        guard let lib, blob.count > 8 else { return nil }
        let limit = min(64, blob.count - 4)
        guard let start = (0..<limit).first(where: { Array(blob[$0..<($0 + 4)]) == magic }) else { return nil }
        let frame = Array(blob[start...])
        return frame.withUnsafeBytes { src -> [UInt8]? in
            let declared = lib.contentSize(src.baseAddress, src.count)
            // UNKNOWN = UInt64.max, ERROR = UInt64.max - 1
            let capacity = declared >= UInt64.max - 1 ? max(1 << 20, frame.count * 32) : Int(min(declared, 256 << 20))
            var out = [UInt8](repeating: 0, count: max(capacity, 1))
            let n = out.withUnsafeMutableBytes { lib.decompress($0.baseAddress, $0.count, src.baseAddress, src.count) }
            guard lib.isError(n) == 0 else { return nil }
            return Array(out.prefix(n))
        }
    }
}
