import Foundation
import NostrProtocol

public struct NostrListSummary: Codable, Equatable, Sendable {
    public let listID: String
    public let accountID: String
    public let kind: Int
    public let pubkey: String
    public let dTag: String
    public let eventID: String
    public let title: String?
    public let visibility: String
    public let privateContent: String?
    public let createdAt: Int
    public let updatedAt: Int

    public init(
        listID: String,
        accountID: String,
        kind: Int,
        pubkey: String,
        dTag: String,
        eventID: String,
        title: String?,
        visibility: String,
        privateContent: String?,
        createdAt: Int,
        updatedAt: Int
    ) {
        self.listID = listID
        self.accountID = accountID
        self.kind = kind
        self.pubkey = pubkey
        self.dTag = dTag
        self.eventID = eventID
        self.title = title
        self.visibility = visibility
        self.privateContent = privateContent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct NostrListItemRecord: Codable, Equatable, Sendable {
    public let listID: String
    public let itemKey: String
    public let itemType: String
    public let value: String
    public let relayHint: String?
    public let visibility: String
    public let position: Int

    public init(
        listID: String,
        itemKey: String,
        itemType: String,
        value: String,
        relayHint: String?,
        visibility: String,
        position: Int
    ) {
        self.listID = listID
        self.itemKey = itemKey
        self.itemType = itemType
        self.value = value
        self.relayHint = relayHint
        self.visibility = visibility
        self.position = position
    }
}

public struct NostrParsedList: Equatable, Sendable {
    public let summary: NostrListSummary
    public let items: [NostrListItemRecord]
}

public enum NostrListParser {
    public static let supportedKinds: Set<Int> = [10_000, 10_003, 10_007, 30_000, 30_002, 30_003]

    public static func parse(event: NostrEvent, accountID: String, updatedAt: Int) -> NostrParsedList? {
        guard supportedKinds.contains(event.kind) else { return nil }

        let dTag = dTag(from: event)
        let listID = listID(kind: event.kind, pubkey: event.pubkey, dTag: dTag)
        let privateContent = event.content.isEmpty ? nil : event.content
        let summary = NostrListSummary(
            listID: listID,
            accountID: accountID,
            kind: event.kind,
            pubkey: event.pubkey,
            dTag: dTag,
            eventID: event.id,
            title: title(from: event, fallbackDTag: dTag),
            visibility: privateContent == nil ? "public" : "public+encrypted",
            privateContent: privateContent,
            createdAt: event.createdAt,
            updatedAt: updatedAt
        )
        let items = event.tags.enumerated().compactMap { position, tag in
            item(from: tag, listID: listID, position: position, kind: event.kind)
        }
        return NostrParsedList(summary: summary, items: items)
    }

    public static func listID(kind: Int, pubkey: String, dTag: String) -> String {
        "\(kind):\(pubkey):\(dTag)"
    }

    public static func dTag(from event: NostrEvent) -> String {
        guard (30_000...39_999).contains(event.kind) else { return "" }
        return event.tags.first { tag in
            tag.count >= 2 && tag[0] == "d"
        }?[1] ?? ""
    }

    private static func title(from event: NostrEvent, fallbackDTag: String) -> String? {
        if let title = event.tags.first(where: { $0.count >= 2 && $0[0] == "title" })?[1],
           !title.isEmpty {
            return title
        }
        return fallbackDTag.isEmpty ? nil : fallbackDTag
    }

    private static func item(from tag: [String], listID: String, position: Int, kind: Int) -> NostrListItemRecord? {
        guard tag.count >= 2 else { return nil }
        guard let itemType = itemType(tagName: tag[0], kind: kind) else { return nil }
        let value = tag[1]
        guard !value.isEmpty else { return nil }
        return NostrListItemRecord(
            listID: listID,
            itemKey: "\(itemType):\(value)",
            itemType: itemType,
            value: value,
            relayHint: relayHint(from: tag),
            visibility: "public",
            position: position
        )
    }

    private static func itemType(tagName: String, kind: Int) -> String? {
        switch kind {
        case 10_000:
            return ["p", "t", "word", "e"].contains(tagName) ? normalizedItemType(tagName) : nil
        case 10_003, 30_003:
            return ["e", "a"].contains(tagName) ? normalizedItemType(tagName) : nil
        case 10_007, 30_002:
            return tagName == "relay" ? "relay" : nil
        case 30_000:
            return tagName == "p" ? "pubkey" : nil
        default:
            return nil
        }
    }

    private static func normalizedItemType(_ tagName: String) -> String {
        switch tagName {
        case "p":
            "pubkey"
        case "e":
            "event"
        case "a":
            "address"
        case "t":
            "hashtag"
        default:
            tagName
        }
    }

    private static func relayHint(from tag: [String]) -> String? {
        guard ["p", "e", "a"].contains(tag[0]), tag.count >= 3, !tag[2].isEmpty else {
            return nil
        }
        return tag[2]
    }
}
