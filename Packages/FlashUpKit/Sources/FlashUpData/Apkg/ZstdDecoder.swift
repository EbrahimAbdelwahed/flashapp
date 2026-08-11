import Foundation
import libzstd

/// Decompresses zstd frames, which is what the modern `.apkg` container uses for its
/// collection database, its media index and every media blob (ADR-004 §2).
///
/// Apple ships no zstd and offers no equivalent, so this is the one place in the package
/// that needs an external C library.
enum ZstdDecoder {
    static let magic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]

    static func isFrame(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return Array(data.prefix(4)) == magic
    }

    /// Decompresses a complete frame.
    ///
    /// When the frame header declares its content size, that size is checked against `limit`
    /// *before* allocating: a 100-byte frame may legitimately declare gigabytes, and that is
    /// precisely the zip-bomb shape the cap exists to stop (ADR-004 §8).
    ///
    /// Anki does not always declare it — the modern `media` index is written as a streaming
    /// frame with no content size — so an undeclared frame falls back to a bounded streaming
    /// decode rather than being refused. The cap is enforced either way.
    static func decompress(_ data: Data, limit: Int, entry: String) throws -> Data {
        guard !data.isEmpty else { return Data() }

        let declared: UInt64 = data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return ZSTD_getFrameContentSize(base, data.count)
        }

        guard declared != ZSTD_CONTENTSIZE_ERROR else {
            throw ApkgError.corruptedData(entry: entry)
        }
        guard declared != ZSTD_CONTENTSIZE_UNKNOWN else {
            return try stream(data, limit: limit, entry: entry)
        }
        guard declared <= UInt64(limit) else {
            throw ApkgError.expandedTooLarge(bytes: Int(min(declared, UInt64(Int.max))), limit: limit)
        }

        let capacity = Int(declared)
        guard capacity > 0 else { return Data() }

        var output = Data(count: capacity)
        let produced: Int = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return ZSTD_decompress(destinationBase, capacity, sourceBase, data.count)
            }
        }

        guard ZSTD_isError(produced) == 0, produced == capacity else {
            throw ApkgError.corruptedData(entry: entry)
        }
        return output
    }

    /// Bounded streaming decode, for frames that do not declare their content size.
    ///
    /// The output grows a chunk at a time and the total is checked against `limit` on every
    /// chunk, so an undeclared frame gets exactly the same protection a declared one does —
    /// the decode stops at the cap instead of exhausting memory.
    private static func stream(_ data: Data, limit: Int, entry: String) throws -> Data {
        guard let dstream = ZSTD_createDStream() else { throw ApkgError.corruptedData(entry: entry) }
        defer { ZSTD_freeDStream(dstream) }
        ZSTD_initDStream(dstream)

        let chunkSize = min(max(ZSTD_DStreamOutSize(), 1), max(limit, 1))
        var output = Data()
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        var finished = false

        try data.withUnsafeBytes { source in
            guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                throw ApkgError.corruptedData(entry: entry)
            }
            var input = ZSTD_inBuffer(src: sourceBase, size: data.count, pos: 0)

            while !finished {
                let status: Int = chunk.withUnsafeMutableBytes { destination -> Int in
                    guard let base = destination.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                    var out = ZSTD_outBuffer(dst: base, size: chunkSize, pos: 0)
                    let code = ZSTD_decompressStream(dstream, &out, &input)
                    if ZSTD_isError(code) != 0 { return -1 }
                    // Appended from the output pointer, not from `chunk`: reading the array
                    // here would overlap its own exclusive access.
                    output.append(base, count: out.pos)
                    // A frame is complete when the decoder asks for nothing more.
                    if code == 0 { finished = true }
                    return Int(out.pos)
                }

                guard status >= 0 else { throw ApkgError.corruptedData(entry: entry) }
                guard output.count <= limit else {
                    throw ApkgError.expandedTooLarge(bytes: output.count, limit: limit)
                }
                // No progress and not finished means a truncated frame.
                if status == 0, !finished, input.pos >= data.count {
                    throw ApkgError.corruptedData(entry: entry)
                }
            }
        }

        return output
    }
}
