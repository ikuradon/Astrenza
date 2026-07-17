import Foundation

public enum NostrRelayURLInputMode: Equatable, Sendable {
    case strict
    case userFacing
}

/// relay identityに使用するcanonical URLです。
///
/// 外部APIとdatabaseは引き続き`String`を使用し、接続やdedupeの境界でこの型へ変換します。
public struct NostrRelayURL: RawRepresentable, Codable, Hashable, Comparable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init?(rawValue: String) {
        self.init(rawValue, mode: .strict)
    }

    public init?(_ input: String, mode: NostrRelayURLInputMode = .strict) {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if mode == .userFacing {
            let lowercaseValue = value.lowercased()
            if lowercaseValue.hasPrefix("https://") {
                value = "wss://" + value.dropFirst("https://".count)
            } else if lowercaseValue.hasPrefix("http://") {
                value = "ws://" + value.dropFirst("http://".count)
            } else if !lowercaseValue.hasPrefix("wss://") &&
                        !lowercaseValue.hasPrefix("ws://") {
                value = "wss://\(value)"
            }
        }

        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        components.scheme = scheme
        components.host = host.hasSuffix(".") ? String(host.dropLast()) : host
        components.fragment = nil
        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.queryItems = components.queryItems?.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return (lhs.value ?? "") < (rhs.value ?? "")
            }
            return lhs.name < rhs.name
        }

        guard let normalized = components.string, !normalized.isEmpty else { return nil }
        rawValue = normalized
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: NostrRelayURL, rhs: NostrRelayURL) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func normalizedStrings(
        _ inputs: [String],
        mode: NostrRelayURLInputMode = .strict
    ) -> [String] {
        var seen = Set<NostrRelayURL>()
        return inputs.compactMap { input in
            guard let relayURL = NostrRelayURL(input, mode: mode),
                  seen.insert(relayURL).inserted
            else { return nil }
            return relayURL.rawValue
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let relayURL = NostrRelayURL(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Nostr relay URL"
            )
        }
        self = relayURL
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
