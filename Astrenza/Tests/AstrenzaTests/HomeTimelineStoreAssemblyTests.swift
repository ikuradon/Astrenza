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
        #expect(components.localMutationCoordinator == nil)
        #expect(components.contentCoordinator.snapshot == .initial)
        #expect(!components.backwardRequestRegistry.hasRequests)
    }

    @Test("An event store enables publishing and database-backed local mutations")
    func assemblesEventStoreCapabilities() throws {
        let eventStore = try NostrEventStore.inMemory()
        let components = assembledHomeTimelineComponents(eventStore: eventStore)
        let mutation = try #require(components.localMutationCoordinator)
        let accountID = String(repeating: "a", count: 64)
        let eventID = String(repeating: "1", count: 64)

        let bookmark = try mutation.bookmarkPost(
            accountID: accountID,
            eventID: eventID,
            at: 100
        )

        #expect(components.eventStore === eventStore)
        #expect(components.publishInteractionWorkflow != nil)
        #expect(try eventStore.localBookmarks(accountID: accountID) == [bookmark])
    }

    @Test("Explicit mutation persistence remains available without a database")
    func assemblesExplicitMutationPersistence() throws {
        let persistence = AssemblyMutationPersistenceSpy()
        let components = assembledHomeTimelineComponents(
            localMutationPersistence: persistence
        )
        let mutation = try #require(components.localMutationCoordinator)

        let rule = try mutation.muteAuthor(
            accountID: "account",
            authorPubkey: "author",
            at: 200
        )

        #expect(components.eventStore == nil)
        #expect(components.publishInteractionWorkflow == nil)
        #expect(persistence.savedRules == [rule])
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
