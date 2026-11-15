import Foundation

/// A stable 64-bit digest of a value's content, used by sync to tell whether something changed
/// (docs/ICLOUD_SYNC.md).
///
/// Unlike `Hasher`, the result is the same on every launch, device and OS version: it only
/// depends on the values a type encodes, in the order it encodes them. Optionals that are `nil`
/// add nothing (synthesized `Codable` skips them), so adding an optional property to a payload
/// later doesn't change the fingerprint of anything saved before.
public enum Fingerprint {
    /// The fingerprint of `value`, with `attachment` (e.g. photo bytes) mixed in when present.
    public static func of(_ value: some Encodable, attachment: Data? = nil) -> Int64 {
        let state = FingerprintState()
        // The encoder never throws; a type that throws from `encode(to:)` on its own just gets a
        // fingerprint of what it wrote before failing.
        try? value.encode(to: FingerprintEncoder(state: state))
        if let attachment {
            state.tag(.attachment)
            state.combine(attachment)
        }
        return Int64(bitPattern: state.hash)
    }
}

/// FNV-1a, 64 bit. Small, fast and fully specified, which is all change detection needs.
final class FingerprintState {
    enum Tag: UInt8 {
        case key = 1, string, integer, unsigned, double, bool, null
        case keyed, unkeyed, element, data, attachment
    }

    private(set) var hash: UInt64 = 0xcbf2_9ce4_8422_2325

    func combine(_ byte: UInt8) {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }

    func tag(_ tag: Tag) {
        combine(tag.rawValue)
    }

    func combine(_ value: UInt64) {
        var value = value
        for _ in 0..<8 {
            combine(UInt8(truncatingIfNeeded: value))
            value >>= 8
        }
    }

    /// Length first, so "ab" + "c" and "a" + "bc" differ.
    func combine(_ data: Data) {
        combine(UInt64(data.count))
        for byte in data {
            combine(byte)
        }
    }

    func combine(_ string: String) {
        var count: UInt64 = 0
        for _ in string.utf8 { count += 1 }
        combine(count)
        for byte in string.utf8 {
            combine(byte)
        }
    }

    func string(_ value: String) {
        tag(.string)
        combine(value)
    }

    func integer(_ value: Int64) {
        tag(.integer)
        combine(UInt64(bitPattern: value))
    }

    func unsigned(_ value: UInt64) {
        tag(.unsigned)
        combine(value)
    }

    func double(_ value: Double) {
        tag(.double)
        // 0.0 and -0.0 compare equal, so they must hash alike.
        combine(value == 0 ? 0 : value.bitPattern)
    }

    func bool(_ value: Bool) {
        tag(.bool)
        combine(value ? 1 : 0 as UInt8)
    }

    /// Dates and data get their own compact form; everything else encodes itself.
    func value(_ value: some Encodable) throws {
        if let date = value as? Date {
            double(date.timeIntervalSinceReferenceDate)
        } else if let data = value as? Data {
            tag(.data)
            combine(data)
        } else {
            try value.encode(to: FingerprintEncoder(state: self))
        }
    }
}

struct FingerprintEncoder: Encoder {
    let state: FingerprintState
    var codingPath: [any CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(Keyed<Key>(state: state))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        Unkeyed(state: state)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        Single(state: state)
    }

    struct Keyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let state: FingerprintState
        var codingPath: [any CodingKey] { [] }

        init(state: FingerprintState) {
            self.state = state
            state.tag(.keyed)
        }

        private func key(_ key: Key) {
            state.tag(.key)
            state.combine(key.stringValue)
        }

        mutating func encodeNil(forKey key: Key) throws { self.key(key); state.tag(.null) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { self.key(key); state.bool(value) }
        mutating func encode(_ value: String, forKey key: Key) throws { self.key(key); state.string(value) }
        mutating func encode(_ value: Double, forKey key: Key) throws { self.key(key); state.double(value) }
        mutating func encode(_ value: Float, forKey key: Key) throws { self.key(key); state.double(Double(value)) }
        mutating func encode(_ value: Int, forKey key: Key) throws { self.key(key); state.integer(Int64(value)) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { self.key(key); state.integer(Int64(value)) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { self.key(key); state.integer(Int64(value)) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { self.key(key); state.integer(Int64(value)) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { self.key(key); state.integer(value) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { self.key(key); state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { self.key(key); state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { self.key(key); state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { self.key(key); state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { self.key(key); state.unsigned(value) }

        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
            self.key(key)
            try state.value(value)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy keyType: NestedKey.Type, forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
            self.key(key)
            return KeyedEncodingContainer(Keyed<NestedKey>(state: state))
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
            self.key(key)
            return Unkeyed(state: state)
        }

        mutating func superEncoder() -> any Encoder { FingerprintEncoder(state: state) }
        mutating func superEncoder(forKey key: Key) -> any Encoder {
            self.key(key)
            return FingerprintEncoder(state: state)
        }
    }

    struct Unkeyed: UnkeyedEncodingContainer {
        let state: FingerprintState
        var codingPath: [any CodingKey] { [] }
        private(set) var count = 0

        init(state: FingerprintState) {
            self.state = state
            state.tag(.unkeyed)
        }

        /// Marks each element, so [[1], [2]] and [[1, 2]] differ.
        private mutating func next() {
            count += 1
            state.tag(.element)
        }

        mutating func encodeNil() throws { next(); state.tag(.null) }
        mutating func encode(_ value: Bool) throws { next(); state.bool(value) }
        mutating func encode(_ value: String) throws { next(); state.string(value) }
        mutating func encode(_ value: Double) throws { next(); state.double(value) }
        mutating func encode(_ value: Float) throws { next(); state.double(Double(value)) }
        mutating func encode(_ value: Int) throws { next(); state.integer(Int64(value)) }
        mutating func encode(_ value: Int8) throws { next(); state.integer(Int64(value)) }
        mutating func encode(_ value: Int16) throws { next(); state.integer(Int64(value)) }
        mutating func encode(_ value: Int32) throws { next(); state.integer(Int64(value)) }
        mutating func encode(_ value: Int64) throws { next(); state.integer(value) }
        mutating func encode(_ value: UInt) throws { next(); state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt8) throws { next(); state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt16) throws { next(); state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt32) throws { next(); state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt64) throws { next(); state.unsigned(value) }

        mutating func encode<T: Encodable>(_ value: T) throws {
            next()
            try state.value(value)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
            next()
            return KeyedEncodingContainer(Keyed<NestedKey>(state: state))
        }

        mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
            next()
            return Unkeyed(state: state)
        }

        mutating func superEncoder() -> any Encoder {
            next()
            return FingerprintEncoder(state: state)
        }
    }

    struct Single: SingleValueEncodingContainer {
        let state: FingerprintState
        var codingPath: [any CodingKey] { [] }

        mutating func encodeNil() throws { state.tag(.null) }
        mutating func encode(_ value: Bool) throws { state.bool(value) }
        mutating func encode(_ value: String) throws { state.string(value) }
        mutating func encode(_ value: Double) throws { state.double(value) }
        mutating func encode(_ value: Float) throws { state.double(Double(value)) }
        mutating func encode(_ value: Int) throws { state.integer(Int64(value)) }
        mutating func encode(_ value: Int8) throws { state.integer(Int64(value)) }
        mutating func encode(_ value: Int16) throws { state.integer(Int64(value)) }
        mutating func encode(_ value: Int32) throws { state.integer(Int64(value)) }
        mutating func encode(_ value: Int64) throws { state.integer(value) }
        mutating func encode(_ value: UInt) throws { state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt8) throws { state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt16) throws { state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt32) throws { state.unsigned(UInt64(value)) }
        mutating func encode(_ value: UInt64) throws { state.unsigned(value) }
        mutating func encode<T: Encodable>(_ value: T) throws { try state.value(value) }
    }
}
