import Foundation
import NostrProtocol

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
