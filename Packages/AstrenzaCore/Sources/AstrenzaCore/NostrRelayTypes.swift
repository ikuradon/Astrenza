import Foundation

public struct NostrRelayRequest: Equatable, Sendable {
    public let subscriptionID: String
    public let filters: [[String: AnySendableJSON]]

    public init(subscriptionID: String, filters: [[String: AnySendableJSON]]) {
        self.subscriptionID = subscriptionID
        self.filters = filters
    }

    public func textFrame() throws -> String {
        var frame: [Any] = ["REQ", subscriptionID]
        frame.append(contentsOf: filters.map { filter in
            filter.mapValues(\.jsonValue)
        })
        let data = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

public enum AnySendableJSON: Equatable, Sendable {
    case int(Int)
    case string(String)
    case strings([String])
    case ints([Int])

    public var jsonValue: Any {
        switch self {
        case .int(let value):
            value
        case .string(let value):
            value
        case .strings(let value):
            value
        case .ints(let value):
            value
        }
    }
}
