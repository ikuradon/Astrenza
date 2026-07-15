import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline profile query interaction")
@MainActor
struct HomeTimelineProfileQueryInteractionTests {
    @Test("Profile cache hits bypass read-context construction")
    func cachePrecedesReadContextConstruction() throws {
        let eventStore = try NostrEventStore.inMemory()
        let pubkey = String(repeating: "a", count: 64)
        let post = NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "post",
            sig: String(repeating: "0", count: 128)
        )
        try eventStore.save(events: [post])
        let readContext = ProfileReadContextSpy()
        let workflow = HomeTimelineQueryInteractionWorkflow(
            repository: HomeTimelineRepository(eventStore: eventStore),
            listProjectionCache: HomeTimelineListProjectionCache(),
            profileProjectionCache: HomeTimelineProfileProjectionCache(),
            readContext: readContext
        )
        let snapshot = HomeTimelineQueryStoreSnapshot(
            accountID: "account",
            fallbackEntries: [],
            resolvedRelayCount: 3,
            syncPolicy: .default(networkType: .wifi),
            homeContentRevision: 7,
            listContentRevision: 2
        )

        let first = workflow.profileProjection(
            pubkey: pubkey,
            isCurrentUser: false,
            postsLimit: 80,
            snapshot: snapshot
        )
        let cached = workflow.profileProjection(
            pubkey: pubkey,
            isCurrentUser: false,
            postsLimit: 80,
            snapshot: snapshot
        )

        #expect(first.posts.map(\.id) == [post.id])
        #expect(cached.profile.id == pubkey)
        #expect(readContext.applicationValues == [true])
    }
}

@MainActor
private final class ProfileReadContextSpy:
    HomeTimelineReadContextProviding {
    private(set) var applicationValues: [Bool] = []

    func context(
        for input: HomeTimelineReadContextInput,
        applyingHomeFilters: Bool
    ) -> HomeTimelineReadContext {
        applicationValues.append(applyingHomeFilters)
        return HomeTimelineReadContext(
            accountID: input.accountID,
            fallbackEntries: input.fallbackEntries,
            metadataEvents: [],
            nip05Resolutions: [:],
            profileResolutionStates: [:],
            followedPubkeys: [],
            resolvedRelayCount: input.resolvedRelayCount,
            filterRules: nil,
            syncPolicy: input.syncPolicy
        )
    }
}
