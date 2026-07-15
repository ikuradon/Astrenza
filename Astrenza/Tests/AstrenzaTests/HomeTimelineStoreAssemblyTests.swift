import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline store assembly")
@MainActor
struct HomeTimelineStoreAssemblyTests {
    @Test("A persistence-free graph keeps optional capabilities disabled")
    func assemblesWithoutPersistence() {
        let components = assembledHomeTimelineComponents()

        #expect(components.eventStore == nil)
        #expect(components.relayRuntime == nil)
        #expect(components.publishInteractionWorkflow == nil)
        #expect(components.localMutationInteractionWorkflow == nil)
        #expect(components.contentCoordinator.snapshot == .initial)
        #expect(!components.backwardRequestRegistry.hasRequests)
        #expect(
            components.feedSyncInteractionWorkflow.activeRequestCount == 0
        )
    }

    @Test("An event store enables publishing and database-backed local mutations")
    func assemblesEventStoreCapabilities() throws {
        let eventStore = try NostrEventStore.inMemory()
        let components = assembledHomeTimelineComponents(eventStore: eventStore)
        let mutation = try #require(
            components.localMutationInteractionWorkflow
        )
        let accountID = String(repeating: "a", count: 64)
        let eventID = String(repeating: "1", count: 64)

        mutation.perform(
            .bookmark(eventID: eventID),
            context: localMutationContext(accountID: accountID)
        )

        #expect(components.eventStore === eventStore)
        #expect(components.publishInteractionWorkflow != nil)
        #expect(
            try eventStore.localBookmarks(accountID: accountID).map(\.eventID)
                == [eventID]
        )
    }

    @Test("Explicit mutation persistence remains available without a database")
    func assemblesExplicitMutationPersistence() throws {
        let persistence = AssemblyMutationPersistenceSpy()
        let components = assembledHomeTimelineComponents(
            localMutationPersistence: persistence
        )
        let mutation = try #require(
            components.localMutationInteractionWorkflow
        )

        mutation.perform(
            .muteAuthor(authorPubkey: "author"),
            context: localMutationContext(accountID: "account")
        )

        #expect(components.eventStore == nil)
        #expect(components.publishInteractionWorkflow == nil)
        #expect(persistence.savedRules.map(\.accountID) == ["account"])
        #expect(persistence.savedRules.map(\.value) == ["author"])
    }
}

@MainActor
private func assembledHomeTimelineComponents(
    eventStore: NostrEventStore? = nil,
    localMutationPersistence: (any HomeTimelineLocalMutationPersisting)? = nil
) -> HomeTimelineStoreComponents {
    HomeTimelineStoreAssembly.assemble(
        HomeTimelineStoreAssemblyInput(
            timelineLoader: NostrHomeTimelineLoader(),
            eventStore: eventStore,
            relayRuntime: nil,
            linkPreviewResolver: nil,
            outboxPublisher: NostrOutboxRelayPublisher(),
            localMutationPersistence: localMutationPersistence,
            syncPolicySettingsStore: .shared
        )
    )
}

@MainActor
private func localMutationContext(
    accountID: String?
) -> HomeLocalMutationInteractionContext {
    HomeLocalMutationInteractionContext(
        state: HomeLocalMutationInteractionState(accountID: accountID),
        effects: HomeLocalMutationInteractionEffects(apply: { _ in })
    )
}

private final class AssemblyMutationPersistenceSpy:
    HomeTimelineLocalMutationPersisting,
    @unchecked Sendable {
    private let lock = NSLock()
    private var rules: [NostrFilterRuleRecord] = []
    private var bookmarks: [NostrLocalBookmarkRecord] = []

    var savedRules: [NostrFilterRuleRecord] {
        lock.withLock { rules }
    }

    func saveFilterRule(_ rule: NostrFilterRuleRecord) throws {
        lock.withLock {
            rules.append(rule)
        }
    }

    func saveLocalBookmark(_ bookmark: NostrLocalBookmarkRecord) throws {
        lock.withLock {
            bookmarks.append(bookmark)
        }
    }
}
