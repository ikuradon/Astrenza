import Foundation
import NostrProtocol

public enum NostrRelayFilterMatcher {
    public static func matches(event: NostrEvent, filters: [[String: AnySendableJSON]]) -> Bool {
        guard !filters.isEmpty else { return false }
        return filters.contains { matches(event: event, filter: $0) }
    }

    public static func matches(event: NostrEvent, filter: [String: AnySendableJSON]) -> Bool {
        for (key, value) in filter {
            switch key {
            case "ids":
                guard value.stringArrayValue.contains(where: { event.id.hasPrefix($0) }) else {
                    return false
                }
            case "authors":
                guard value.stringArrayValue.contains(where: { event.pubkey.hasPrefix($0) }) else {
                    return false
                }
            case "kinds":
                guard value.intArrayValue.contains(event.kind) else { return false }
            case "since":
                guard let since = value.intValue, event.createdAt >= since else { return false }
            case "until":
                guard let until = value.intValue, event.createdAt <= until else { return false }
            case "limit", "search":
                continue
            default:
                if key.hasPrefix("#") {
                    let tagName = String(key.dropFirst())
                    let allowedValues = value.stringArrayValue
                    guard event.tags.contains(where: { tag in
                        tag.count >= 2 && tag[0] == tagName && allowedValues.contains(tag[1])
                    }) else { return false }
                } else {
                    return false
                }
            }
        }
        return true
    }
}

public extension AnySendableJSON {
    var stringArrayValue: [String] {
        switch self {
        case .string(let value):
            [value]
        case .strings(let values):
            values
        case .int, .ints:
            []
        }
    }

    var intArrayValue: [Int] {
        switch self {
        case .int(let value):
            [value]
        case .ints(let values):
            values
        case .string, .strings:
            []
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            value
        case .string(let value):
            Int(value)
        case .ints, .strings:
            nil
        }
    }
}
