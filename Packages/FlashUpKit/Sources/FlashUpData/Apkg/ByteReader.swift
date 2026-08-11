import Foundation

/// Bounds-checked little-endian reads over untrusted bytes.
///
/// An `.apkg` arrives from the internet, so every offset in it is hostile until proven
/// otherwise. Each read returns `nil` rather than trapping, which is what lets the ZIP and
/// protobuf readers stay free of force unwraps (spec §0.2 makes `force_unwrapping` an error).
struct ByteReader {
    private let bytes: [UInt8]

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    var count: Int { bytes.count }

    func byte(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < bytes.count else { return nil }
        return bytes[offset]
    }

    func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    func uint32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        var value: UInt32 = 0
        for index in stride(from: 3, through: 0, by: -1) {
            value = (value << 8) | UInt32(bytes[offset + index])
        }
        return value
    }

    func slice(at offset: Int, count length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset + length <= bytes.count else { return nil }
        return Data(bytes[offset ..< offset + length])
    }

    /// Scans backwards for a 4-byte signature, which is how a ZIP end-of-central-directory
    /// record has to be found: it sits before a comment of unknown length.
    func lastIndex(of signature: UInt32, notBefore lowerBound: Int) -> Int? {
        guard bytes.count >= 4 else { return nil }
        var offset = bytes.count - 4
        while offset >= max(0, lowerBound) {
            if uint32(at: offset) == signature { return offset }
            offset -= 1
        }
        return nil
    }
}
