import AstrenzaCore
import Foundation

enum TimelineRichContentRoute: Equatable {
    case external(URL)
    case profile(pubkey: String, relays: [String])
    case event(eventID: String, relays: [String], author: String?, kind: Int?)
    case hashtag(String)
    case unsupported

    init(url: URL) {
        guard url.scheme == "astrenza" else {
            self = .external(url)
            return
        }

        let value = url.pathComponents.dropFirst().first ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let relays = queryItems.filter { $0.name == "relay" }.compactMap(\.value)

        switch url.host {
        case "profile":
            self = value.isEmpty ? .unsupported : .profile(pubkey: value, relays: relays)
        case "event":
            let author = queryItems.first { $0.name == "author" }?.value
            let kind = queryItems.first { $0.name == "kind" }?.value.flatMap(Int.init)
            self = value.isEmpty ? .unsupported : .event(eventID: value, relays: relays, author: author, kind: kind)
        case "hashtag":
            self = value.isEmpty ? .unsupported : .hashtag(value)
        default:
            self = .unsupported
        }
    }

    static func url(for token: NostrRichContentToken) -> URL? {
        switch token {
        case .url(let url):
            url
        case .hashtag(let hashtag):
            internalURL(host: "hashtag", value: hashtag)
        case .profile(let pubkey, let relays):
            internalURL(host: "profile", value: pubkey, relays: relays)
        case .event(let eventID, let relays, let author, let kind):
            internalURL(host: "event", value: eventID, relays: relays, author: author, kind: kind)
        case .text, .customEmoji:
            nil
        }
    }

    private static func internalURL(
        host: String,
        value: String,
        relays: [String] = [],
        author: String? = nil,
        kind: Int? = nil
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "astrenza"
        components.host = host
        components.path = "/\(value)"

        var queryItems = relays.map { URLQueryItem(name: "relay", value: $0) }
        if let author {
            queryItems.append(URLQueryItem(name: "author", value: author))
        }
        if let kind {
            queryItems.append(URLQueryItem(name: "kind", value: String(kind)))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }
}
