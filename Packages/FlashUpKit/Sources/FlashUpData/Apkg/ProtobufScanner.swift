import Foundation

/// A read-only scanner over protobuf wire format, big enough for the three tiny messages an
/// `.apkg` puts in our way and no bigger:
///
/// - `meta` — the container version (field 1, varint);
/// - the modern `media` index — repeated entries of `{name, size, sha1}`;
/// - a schema-18 notetype `config` — whose field 1 says whether the note type is cloze.
///
/// Pulling in a protobuf runtime and generating Anki's `.proto` files would mean tracking
/// their schema forever, for three fields whose meaning is fixed by the file format.
enum ProtobufScanner {
    enum WireType: UInt64 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case startGroup = 3
        case endGroup = 4
        case fixed32 = 5
    }

    enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    struct Field {
        let number: Int
        let value: Value
    }

    /// Walks the top-level fields of a message. Unknown fields are skipped, exactly as a
    /// real protobuf reader would, so a future Anki version adding fields cannot break us.
    static func fields(in data: Data) -> [Field] {
        let reader = ByteReader(data)
        var offset = 0
        var fields: [Field] = []

        while offset < reader.count {
            guard let (key, afterKey) = varint(reader, at: offset) else { return fields }
            offset = afterKey

            let number = Int(key >> 3)
            guard number > 0, let wire = WireType(rawValue: key & 0x07) else { return fields }

            switch wire {
            case .varint:
                guard let (value, next) = varint(reader, at: offset) else { return fields }
                fields.append(Field(number: number, value: .varint(value)))
                offset = next
            case .lengthDelimited:
                guard let (length, afterLength) = varint(reader, at: offset),
                      length <= UInt64(Int.max),
                      let payload = reader.slice(at: afterLength, count: Int(length)) else {
                    return fields
                }
                fields.append(Field(number: number, value: .bytes(payload)))
                offset = afterLength + Int(length)
            case .fixed64:
                offset += 8
            case .fixed32:
                offset += 4
            case .startGroup, .endGroup:
                // Groups are deprecated and Anki emits none; stopping beats mis-parsing.
                return fields
            }
        }

        return fields
    }

    static func varintValue(_ number: Int, in data: Data) -> UInt64? {
        for field in fields(in: data) where field.number == number {
            if case let .varint(value) = field.value { return value }
        }
        return nil
    }

    static func byteValues(_ number: Int, in data: Data) -> [Data] {
        fields(in: data).compactMap { field in
            guard field.number == number, case let .bytes(payload) = field.value else { return nil }
            return payload
        }
    }

    static func stringValue(_ number: Int, in data: Data) -> String? {
        for field in fields(in: data) where field.number == number {
            if case let .bytes(payload) = field.value {
                return String(data: payload, encoding: .utf8)
            }
        }
        return nil
    }

    private static func varint(_ reader: ByteReader, at offset: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var cursor = offset

        // A varint is at most ten bytes; anything longer is corrupt, not merely unusual.
        while shift <= 63 {
            guard let byte = reader.byte(at: cursor) else { return nil }
            result |= UInt64(byte & 0x7F) << shift
            cursor += 1
            if byte & 0x80 == 0 { return (result, cursor) }
            shift += 7
        }
        return nil
    }
}
