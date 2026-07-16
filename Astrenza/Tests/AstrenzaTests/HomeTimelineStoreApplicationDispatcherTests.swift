import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline store application dispatcher")
@MainActor
struct HomeStoreApplicationDispatcherTests {
    @Test("State applications preserve command order and payloads")
    func stateApplicationsDispatchEffects() {
        let fixture = StoreApplicationDispatcherFixture()
        let account = fixture.account
        let transition = fixture.presentationTransition
        let content = fixture.contentSnapshot
        let relaySnapshot = fixture.relaySnapshot
        let relayTransition = fixture.relayTransition

        let applications: [HomeTimelineStateInteractionApplication] = [
            .applyPresentationTransition(transition),
            .applyContentSnapshot(content),
            .applyRelayStatusSnapshot(relaySnapshot),
            .applyListProjectionInvalidation(
                HomeTimelineListProjectionInvalidation(revision: 4)
            ),
            .applyPendingEventCountPublication(
                HomeTimelinePendingEventCountPublication(count: 3)
            ),
            .reloadProjection(account: account, anchorEventID: "anchor"),
            .requestNewestProjectionReload,
            .scheduleMaterialization(
                delayNanoseconds: 120,
                allowsRealtimeFollow: true
            ),
            .materializeEntries,
            .applyRelayStatusTransition(relayTransition)
        ]
        for application in applications {
            fixture.dispatcher.apply(application, effects: fixture.effects)
        }

        #expect(fixture.probe.events == [
            .presentation(changes: transition.changes.rawValue),
            .contentRelays(content.resolvedRelays),
            .relaySnapshot(plannedCount: relaySnapshot.plannedRelayCount),
            .listRevision(4),
            .pendingCount(3),
            .reloadProjection(
                accountID: account.pubkey,
                anchorEventID: "anchor",
                mergingWithCurrentWindow: false
            ),
            .requestNewestProjectionReload,
            .scheduleMaterialization(
                delayNanoseconds: 120,
                allowsRealtimeFollow: true
            ),
            .materializeEntries,
            .relayTransition(relayTransition)
        ])
    }

    @Test("Runtime applications preserve payloads and default scheduling")
    func runtimeApplicationsDispatchEffects() {
        let fixture = StoreApplicationDispatcherFixture()
        let completion = fixture.backwardCompletion

        fixture.dispatcher.apply(
            HomeTimelineRuntimeStoreAction.setRealtime(true),
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            .applyRelayStatusTransition(nil),
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            .handleBackwardCompletion(completion),
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            HomeTimelineRuntimeStoreAction.publishProfileMetadataChange,
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            HomeTimelineRuntimeStoreAction.invalidateListEntries,
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            .scheduleMaterialization,
            effects: fixture.effects
        )
        fixture.dispatcher.apply(
            HomeTimelineRuntimeStoreAction.scheduleLinkPreviewResolution,
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .setRealtime(true),
            .relayTransition(nil),
            .backwardCompletion(completion),
            .publishProfileMetadataChange,
            .invalidateListEntries,
            .scheduleMaterialization(
                delayNanoseconds: nil,
                allowsRealtimeFollow: nil
            ),
            .scheduleLinkPreviewResolution
        ])
    }

    @Test("Feature applications preserve domain payloads and order")
    func featureApplicationsDispatchEffects() {
        let fixture = StoreApplicationDispatcherFixture()
        let relayTransition = fixture.relayTransition
        let phase = NostrHomeTimelinePhase.failed("mutation failed")

        fixture.dispatcher.apply(
            HomeTimelineLinkPreviewStoreAction.applyRelayStatusTransition(
                relayTransition
            ),
            effects: fixture.effects
        )
        let filterActions: [HomeTimelineFilterStoreAction] = [
            .invalidateListEntries,
            .materializeEntries
        ]
        for action in filterActions {
            fixture.dispatcher.apply(action, effects: fixture.effects)
        }
        fixture.dispatcher.apply(
            HomeTimelineSyncStoreAction.setRealtime(true),
            effects: fixture.effects
        )
        let mutationActions: [HomeTimelineLocalMutationStoreAction] = [
            .invalidateListEntries,
            .materializeEntries,
            .setPhase(phase)
        ]
        for action in mutationActions {
            fixture.dispatcher.apply(action, effects: fixture.effects)
        }

        #expect(fixture.probe.events == [
            .relayTransition(relayTransition),
            .invalidateListEntries,
            .materializeEntries,
            .setRealtime(true),
            .invalidateListEntries,
            .materializeEntries,
            .setPhase(phase)
        ])
    }

    @Test("Gap applications preserve relay anchor and order")
    func gapApplicationsDispatchEffects() {
        let fixture = StoreApplicationDispatcherFixture()
        let actions: [HomeTimelineGapBackfillStoreAction] = [
            .applyRelayStatusTransition(fixture.relayTransition),
            .reloadProjection(
                account: fixture.account,
                anchorEventID: "gap-anchor"
            ),
            .materializeEntries
        ]

        for action in actions {
            fixture.dispatcher.apply(action, effects: fixture.effects)
        }

        #expect(fixture.probe.events == [
            .relayTransition(fixture.relayTransition),
            .reloadProjection(
                accountID: fixture.account.pubkey,
                anchorEventID: "gap-anchor",
                mergingWithCurrentWindow: false
            ),
            .materializeEntries
        ])
    }

    @Test("Publish applications preserve state and persistence order")
    func publishApplicationsDispatchEffects() async {
        let fixture = StoreApplicationDispatcherFixture()
        let actions: [HomeTimelinePublishStoreAction] = [
            .applyContentSnapshot(fixture.contentSnapshot),
            .reloadNewestProjectionWindow(fixture.account),
            .materializeEntries,
            .setPhase(.loaded)
        ]

        for action in actions {
            fixture.dispatcher.apply(action, effects: fixture.effects)
        }
        await fixture.dispatcher.perform(
            HomeTimelinePublishAsyncAction.persistDatabase(fixture.account),
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .contentRelays(fixture.contentSnapshot.resolvedRelays),
            .reloadNewestProjectionWindow(fixture.account.pubkey),
            .materializeEntries,
            .setPhase(.loaded),
            .persistDatabase(fixture.account.pubkey)
        ])
    }

    @Test("Backward applications preserve merge policy and order")
    func backwardApplicationsDispatchEffects() {
        let fixture = StoreApplicationDispatcherFixture()
        let actions: [HomeTimelineBackwardStoreAction] = [
            .applyContentSnapshot(fixture.contentSnapshot),
            .applyRelayStatusTransition(fixture.relayTransition),
            .reloadProjection(
                account: fixture.account,
                anchorEventID: "backward-anchor",
                mergingWithCurrentWindow: true
            ),
            .materializeEntries,
            .scheduleLinkPreviewResolution,
            .incrementRelayStatusRevision
        ]

        for action in actions {
            fixture.dispatcher.apply(action, effects: fixture.effects)
        }

        #expect(fixture.probe.events == [
            .contentRelays(fixture.contentSnapshot.resolvedRelays),
            .relayTransition(fixture.relayTransition),
            .reloadProjection(
                accountID: fixture.account.pubkey,
                anchorEventID: "backward-anchor",
                mergingWithCurrentWindow: true
            ),
            .materializeEntries,
            .scheduleLinkPreviewResolution,
            .publishRelayStatusChange
        ])
    }

    @Test("Async runtime event preserves relay subscription and event")
    func asyncRuntimeEventDispatchesEffect() async {
        let fixture = StoreApplicationDispatcherFixture()
        let event = fixture.event

        await fixture.dispatcher.perform(
            .handleEvent(
                relayURL: "wss://relay.example",
                subscriptionID: "home-subscription",
                event: event
            ),
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .runtimeEvent(
                relayURL: "wss://relay.example",
                subscriptionID: "home-subscription",
                eventID: event.id
            )
        ])
    }
}
