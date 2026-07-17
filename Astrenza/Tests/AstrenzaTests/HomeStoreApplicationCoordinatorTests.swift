import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home Store application coordinator")
@MainActor
struct HomeStoreApplicationCoordinatorTests {
    @Test("Composition-owned applications receive context effects")
    func compositionRoutesContextEffects() {
        let fixture = StoreApplicationCoordinatorFixture()
        let snapshot = HomeTimelineContentSnapshot(
            resolvedRelays: ["wss://relay.example"],
            followedPubkeys: ["followed-author"],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: false
        )

        fixture.composition.context.stateContext().effects.apply(
            .applyContentSnapshot(snapshot)
        )

        let content = fixture.components.publishedStateCoordinator.content
        #expect(content.resolvedRelays == snapshot.resolvedRelays)
        #expect(content.followedPubkeys == snapshot.followedPubkeys)
        #expect(content.hasMoreOlder == snapshot.hasMoreOlder)
    }

    @Test("Compound state applications keep internal and published state aligned")
    func compoundStateApplicationsStayAligned() {
        let fixture = StoreApplicationCoordinatorFixture()
        let followedPubkeys = ["first-author", "second-author"]

        fixture.composition.application.replaceFollowedPubkeys(
            followedPubkeys
        )

        #expect(
            fixture.components.dataInteractionWorkflow.contentState
                .followedPubkeys == followedPubkeys
        )
        #expect(
            fixture.components.publishedStateCoordinator.content
                .followedPubkeys == followedPubkeys
        )
    }

    @Test("Query invalidation is published by the application boundary")
    func queryInvalidationIsPublished() {
        let fixture = StoreApplicationCoordinatorFixture()
        let previousRevision = fixture.components.publishedStateCoordinator
            .listProjection.revision

        fixture.composition.application.invalidateListEntries()

        #expect(
            fixture.components.publishedStateCoordinator.listProjection
                .revision > previousRevision
        )
    }
}

@MainActor
private struct StoreApplicationCoordinatorFixture {
    let components: HomeTimelineStoreComponents
    let composition: HomeStoreComposition

    init() {
        let components = HomeTimelineStoreAssembly.assemble(
            HomeTimelineStoreAssemblyInput(
                timelineLoader: NostrHomeTimelineLoader(),
                eventStore: nil,
                startupFailureMessage: nil,
                relayRuntime: nil,
                linkPreviewResolver: nil,
                viewportStateRestorer: TimelineRestoreStore(),
                outboxPublisher: NostrOutboxRelayPublisher(),
                localMutationPersistence: nil,
                initialSyncPolicy: .default(networkType: .unknown),
                syncPolicySettingsStore: .shared
            )
        )
        self.components = components
        self.composition = HomeStoreComposition.make(components: components)
    }
}
