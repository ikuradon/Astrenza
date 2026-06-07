import CryptoKit
import Foundation

public struct NostrAccount: Codable, Equatable, Sendable {
    public let pubkey: String
    public let displayIdentifier: String
    public let readOnly: Bool
    public let discoveryRelays: [String]

    public init(pubkey: String, displayIdentifier: String, readOnly: Bool, discoveryRelays: [String] = []) {
        self.pubkey = pubkey
        self.displayIdentifier = displayIdentifier
        self.readOnly = readOnly
        self.discoveryRelays = discoveryRelays
    }

    enum CodingKeys: String, CodingKey {
        case pubkey
        case displayIdentifier
        case readOnly
        case discoveryRelays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pubkey = try container.decode(String.self, forKey: .pubkey)
        displayIdentifier = try container.decode(String.self, forKey: .displayIdentifier)
        readOnly = try container.decode(Bool.self, forKey: .readOnly)
        discoveryRelays = try container.decodeIfPresent([String].self, forKey: .discoveryRelays) ?? []
    }
}

public struct NostrEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let pubkey: String
    public let createdAt: Int
    public let kind: Int
    public let tags: [[String]]
    public let content: String
    public let sig: String

    enum CodingKeys: String, CodingKey {
        case id
        case pubkey
        case createdAt = "created_at"
        case kind
        case tags
        case content
        case sig
    }

    public init(id: String, pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String, sig: String) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
        self.sig = sig
    }

    public var computedID: String {
        let canonical = NostrCanonicalJSON.serialize(
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public var hasValidShape: Bool {
        NostrHex.isLowercaseHex(id, byteCount: 32)
            && NostrHex.isLowercaseHex(pubkey, byteCount: 32)
            && NostrHex.isLowercaseHex(sig, byteCount: 64)
            && computedID == id
    }
}

public enum NostrCanonicalJSON {
    public static func serialize(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) -> String {
        "[0,\(escaped(pubkey)),\(createdAt),\(kind),\(serializeTags(tags)),\(escaped(content))]"
    }

    private static func serializeTags(_ tags: [[String]]) -> String {
        "[" + tags.map { tag in
            "[" + tag.map(escaped).joined(separator: ",") + "]"
        }.joined(separator: ",") + "]"
    }

    private static func escaped(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08:
                output += "\\b"
            case 0x09:
                output += "\\t"
            case 0x0A:
                output += "\\n"
            case 0x0C:
                output += "\\f"
            case 0x0D:
                output += "\\r"
            case 0x22:
                output += "\\\""
            case 0x5C:
                output += "\\\\"
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
        return output
    }
}

public enum NostrHex {
    public static func isLowercaseHex(_ value: String, byteCount: Int) -> Bool {
        value.count == byteCount * 2
            && value.allSatisfy { character in
                ("0"..."9").contains(character) || ("a"..."f").contains(character)
            }
    }

    public static func bytes(fromLowercaseHex value: String) -> [UInt8]? {
        guard value.count.isMultiple(of: 2),
              value.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) })
        else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    public static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public enum NostrNIP19Error: Error, Equatable {
    case unsupportedPrefix(String)
    case invalidEncoding
    case invalidChecksum
    case invalidPayloadLength(Int)
}

public enum NostrNIP19 {
    public static func publicKeyHex(from input: String) throws -> String {
        try hexPayload(from: input, prefix: "npub")
    }

    public static func privateKeyHex(from input: String) throws -> String {
        try hexPayload(from: input, prefix: "nsec")
    }

    public static func eventIDHex(from input: String) throws -> String {
        try hexPayload(from: input, prefix: "note")
    }

    private static func hexPayload(from input: String, prefix: String) throws -> String {
        let lowered = normalizedInput(input)
        if NostrHex.isLowercaseHex(lowered, byteCount: 32) {
            return lowered
        }
        let decoded = try Bech32.decode(lowered)
        guard decoded.hrp == prefix else {
            throw NostrNIP19Error.unsupportedPrefix(decoded.hrp)
        }
        let bytes = try Bech32.convertBits(decoded.data, from: 5, to: 8, pad: false)
        guard bytes.count == 32 else {
            throw NostrNIP19Error.invalidPayloadLength(bytes.count)
        }
        return NostrHex.hexString(bytes)
    }

    private static func normalizedInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("nostr:") ? String(trimmed.dropFirst("nostr:".count)) : trimmed
        return value.lowercased()
    }
}

enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generators: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

    static func decode(_ input: String) throws -> (hrp: String, data: [UInt8]) {
        guard let separator = input.lastIndex(of: "1") else {
            throw NostrNIP19Error.invalidEncoding
        }
        let hrp = String(input[..<separator])
        let encoded = input[input.index(after: separator)...]
        guard !hrp.isEmpty, encoded.count >= 6 else {
            throw NostrNIP19Error.invalidEncoding
        }

        let values = try encoded.map { character -> UInt8 in
            guard let index = charset.firstIndex(of: character) else {
                throw NostrNIP19Error.invalidEncoding
            }
            return UInt8(index)
        }
        guard polymod(hrpExpand(hrp) + values) == 1 else {
            throw NostrNIP19Error.invalidChecksum
        }
        return (hrp, Array(values.dropLast(6)))
    }

    static func convertBits(_ input: [UInt8], from: Int, to: Int, pad: Bool) throws -> [UInt8] {
        var accumulator = 0
        var bits = 0
        var output: [UInt8] = []
        let maxValue = (1 << to) - 1
        let maxAccumulator = (1 << (from + to - 1)) - 1

        for value in input {
            guard Int(value) >> from == 0 else {
                throw NostrNIP19Error.invalidEncoding
            }
            accumulator = ((accumulator << from) | Int(value)) & maxAccumulator
            bits += from
            while bits >= to {
                bits -= to
                output.append(UInt8((accumulator >> bits) & maxValue))
            }
        }

        if pad {
            if bits > 0 {
                output.append(UInt8((accumulator << (to - bits)) & maxValue))
            }
        } else if bits >= from || ((accumulator << (to - bits)) & maxValue) != 0 {
            throw NostrNIP19Error.invalidEncoding
        }

        return output
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let scalars = hrp.unicodeScalars.map { UInt8($0.value) }
        return scalars.map { $0 >> 5 } + [0] + scalars.map { $0 & 31 }
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = (checksum & 0x1ffffff) << 5 ^ UInt32(value)
            for index in 0..<5 where ((top >> UInt32(index)) & 1) == 1 {
                checksum ^= generators[index]
            }
        }
        return checksum
    }
}

public struct NostrRelayList: Equatable {
    public let items: [Item]

    public struct Item: Equatable {
        public let url: String
        public let canRead: Bool
        public let canWrite: Bool

        public init(url: String, canRead: Bool, canWrite: Bool) {
            self.url = url
            self.canRead = canRead
            self.canWrite = canWrite
        }
    }

    public init(items: [Item]) {
        self.items = items
    }

    public var readRelays: [String] {
        dedupe(items.filter(\.canRead).map(\.url))
    }

    public var writeRelays: [String] {
        dedupe(items.filter(\.canWrite).map(\.url))
    }

    public static func parse(from event: NostrEvent?) -> NostrRelayList {
        guard let event, event.kind == 10002 else {
            return NostrRelayList(items: [])
        }

        let items = event.tags.compactMap { tag -> Item? in
            guard tag.count >= 2, tag[0] == "r", let normalized = normalizeRelayURL(tag[1]) else {
                return nil
            }
            let marker = tag.count >= 3 ? tag[2] : nil
            return Item(
                url: normalized,
                canRead: marker != "write",
                canWrite: marker != "read"
            )
        }
        return NostrRelayList(items: dedupeItems(items))
    }

    private static func normalizeRelayURL(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://") {
            value = "wss://" + value.dropFirst("https://".count)
        } else if value.hasPrefix("http://") {
            value = "ws://" + value.dropFirst("http://".count)
        } else if !value.hasPrefix("wss://") && !value.hasPrefix("ws://") {
            value = "wss://\(value)"
        }
        guard let url = URL(string: value), url.scheme == "wss" || url.scheme == "ws", url.host != nil else {
            return nil
        }
        return value
    }

    private static func dedupeItems(_ items: [Item]) -> [Item] {
        var seen = Set<String>()
        var result: [Item] = []
        for item in items where seen.insert(item.url).inserted {
            result.append(item)
        }
        return result
    }

    private func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}

public enum NostrContactList {
    public static func pubkeys(from event: NostrEvent?) -> [String] {
        guard let event, event.kind == 3 else {
            return []
        }

        var seen = Set<String>()
        var result: [String] = []
        for tag in event.tags where tag.count >= 2 && tag[0] == "p" {
            let pubkey = tag[1].lowercased()
            guard NostrHex.isLowercaseHex(pubkey, byteCount: 32), seen.insert(pubkey).inserted else {
                continue
            }
            result.append(pubkey)
        }
        return result
    }
}

public struct NostrProfileMetadata: Decodable, Equatable {
    public let name: String?
    public let displayName: String?
    public let display_name: String?
    public let nip05: String?
    public let picture: String?

    public var bestName: String? {
        [displayName, display_name, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    public var pictureURL: URL? {
        guard let rawPicture = picture?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPicture.isEmpty,
              let components = URLComponents(string: rawPicture),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false,
              let url = components.url
        else { return nil }

        return url
    }
}
