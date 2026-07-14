import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline filter coordinator")
@MainActor
struct HomeTimelineFilterCoordinatorTests {
    @Test("Projection loads Home rules and counts warning and hidden matches")
    func projectionLoadsHomeRulesAndCountsMatches() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        try eventStore.saveFilterRule(
            rule(
                id: "warning",
                accountID: accountID,
                value: "caution",
                presentation: .maskWithWarning,
                scopes: [.home]
            )
        )
        try eventStore.saveFilterRule(
            rule(
                id: "hidden",
                accountID: accountID,
                value: "blocked",
                presentation: .hide,
                scopes: [.home]
            )
        )
        try eventStore.saveFilterRule(
            rule(
                id: "lists-only",
                accountID: accountID,
                value: "list",
                presentation: .hide,
                scopes: [.lists]
            )
        )
        let events = [
            event(id: "1", content: "caution content"),
            event(id: "2", content: "blocked content"),
            event(id: "3", content: "list content")
        ]
        let coordinator = HomeTimelineFilterCoordinator(eventStore: eventStore)

        let projection = coordinator.projection(
            accountID: accountID,
            events: events,
            now: 100
        )

        #expect(Set(projection.effectiveRuleSet?.rules.map(\.ruleID) ?? []) == [
            "warning",
            "hidden"
        ])
        #expect(projection.status.activeRuleCount == 2)
        #expect(projection.status.warningMatchCount == 1)
        #expect(projection.status.hiddenMatchCount == 1)
        #expect(!projection.status.isSuspended)
    }

    @Test("Projection merges cached public NIP-51 mute items")
    func projectionMergesCachedPublicMuteItems() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "b", count: 64)
        let mutedPubkey = String(repeating: "c", count: 64)
        let muteList = event(
            id: "4",
            pubkey: accountID,
            createdAt: 90,
            kind: 10_000,
            tags: [["p", mutedPubkey], ["word", "noise"]]
        )
        try eventStore.save(events: [muteList])
        let coordinator = HomeTimelineFilterCoordinator(eventStore: eventStore)

        let projection = coordinator.projection(
            accountID: accountID,
            events: [event(id: "5", pubkey: mutedPubkey, content: "ordinary")],
            now: 100
        )

        #expect(Set(projection.effectiveRuleSet?.rules.map(\.kind) ?? []) == [
            .mutedPubkey,
            .keyword
        ])
        #expect(projection.status.activeRuleCount == 2)
        #expect(projection.status.warningMatchCount == 1)
        #expect(projection.status.hiddenMatchCount == 0)
    }

    @Test("Suspension is idempotent and preserves active rule visibility")
    func suspensionIsIdempotentAndPreservesActiveRuleVisibility() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "d", count: 64)
        try eventStore.saveFilterRule(
            rule(
                id: "hidden",
                accountID: accountID,
                value: "blocked",
                presentation: .hide,
                scopes: [.home]
            )
        )
        let event = event(id: "6", content: "blocked content")
        let coordinator = HomeTimelineFilterCoordinator(eventStore: eventStore)

        #expect(coordinator.suspend())
        #expect(!coordinator.suspend())
        let suspended = coordinator.projection(
            accountID: accountID,
            events: [event],
            now: 100
        )

        #expect(suspended.effectiveRuleSet == nil)
        #expect(suspended.status.activeRuleCount == 1)
        #expect(suspended.status.hiddenMatchCount == 0)
        #expect(suspended.status.isSuspended)

        #expect(coordinator.resume())
        #expect(!coordinator.resume())
        let resumed = coordinator.projection(
            accountID: accountID,
            events: [event],
            now: 100
        )

        #expect(resumed.effectiveRuleSet != nil)
        #expect(resumed.status.hiddenMatchCount == 1)
        #expect(!resumed.status.isSuspended)

        coordinator.suspend()
        coordinator.reset()

        #expect(coordinator.effectiveRuleSet(accountID: accountID, now: 100) != nil)
    }

    @Test("Missing account or persistence produces an empty projection")
    func missingContextProducesEmptyProjection() throws {
        let eventStore = try NostrEventStore.inMemory()
        let event = event(id: "7", content: "content")

        let missingAccount = HomeTimelineFilterCoordinator(
            eventStore: eventStore
        ).projection(accountID: nil, events: [event], now: 100)
        let missingPersistence = HomeTimelineFilterCoordinator(
            eventStore: nil
        ).projection(
            accountID: String(repeating: "e", count: 64),
            events: [event],
            now: 100
        )

        #expect(missingAccount == HomeTimelineFilterProjection(
            effectiveRuleSet: nil,
            status: TimelineFilterStatus()
        ))
        #expect(missingPersistence == HomeTimelineFilterProjection(
            effectiveRuleSet: nil,
            status: TimelineFilterStatus()
        ))
    }

    private func rule(
        id: String,
        accountID: String,
        value: String,
        presentation: NostrFilterRulePresentation,
        scopes: Set<NostrFilterTimelineScope>
    ) -> NostrFilterRuleRecord {
        NostrFilterRuleRecord(
            ruleID: id,
            accountID: accountID,
            kind: .keyword,
            value: value,
            presentation: presentation,
            scopes: scopes,
            createdAt: 1,
            updatedAt: 1
        )
    }

    private func event(
        id: Character,
        pubkey: String = String(repeating: "f", count: 64),
        createdAt: Int = 100,
        kind: Int = 1,
        tags: [[String]] = [],
        content: String = ""
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(id), count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "0", count: 128)
        )
    }
}
