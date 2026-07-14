import AstrenzaCore
import Foundation

protocol HomeTimelineLocalMutationPersisting: Sendable {
    func saveFilterRule(_ rule: NostrFilterRuleRecord) throws
    func saveLocalBookmark(_ bookmark: NostrLocalBookmarkRecord) throws
}

extension NostrEventStore: HomeTimelineLocalMutationPersisting {}

struct HomeTimelineLocalMutationCoordinator: Sendable {
    private let persistence: any HomeTimelineLocalMutationPersisting

    init(persistence: any HomeTimelineLocalMutationPersisting) {
        self.persistence = persistence
    }

    @discardableResult
    func muteAuthor(
        accountID: String,
        authorPubkey: String,
        at timestamp: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrFilterRuleRecord {
        let rule = NostrFilterRuleRecord(
            ruleID: "local:mute-pubkey:\(accountID):\(authorPubkey)",
            accountID: accountID,
            kind: .mutedPubkey,
            value: authorPubkey,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try persistence.saveFilterRule(rule)
        return rule
    }

    @discardableResult
    func bookmarkPost(
        accountID: String,
        eventID: String,
        at timestamp: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrLocalBookmarkRecord {
        let bookmark = NostrLocalBookmarkRecord(
            accountID: accountID,
            eventID: eventID,
            createdAt: timestamp
        )
        try persistence.saveLocalBookmark(bookmark)
        return bookmark
    }
}
