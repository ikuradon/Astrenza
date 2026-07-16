import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline store application effects factory")
@MainActor
struct HomeStoreApplicationEffectsFactoryTests {
    @Test("Every application effect forwards payloads in call order")
    func forwardsEveryEffect() async {
        let fixture = StoreApplicationDispatcherFixture()
        let target = StoreApplicationEffectTargetSpy()
        let effects = HomeStoreApplicationEffectsFactory.make(
            target: target
        )
        let phase = NostrHomeTimelinePhase.failed("factory")

        applyProjectionEffects(effects, fixture: fixture)
        applyRuntimeEffects(effects, fixture: fixture, phase: phase)
        await applyAsyncEffects(effects, fixture: fixture)

        let expectedEvents =
            expectedProjectionEvents(fixture) +
            expectedRuntimeEvents(fixture, phase: phase) +
            expectedAsyncEvents(fixture)
        #expect(target.events == expectedEvents)
        #expect(!target.receivedProjectionCompletion)
        #expect(target.materializationArguments == [
            MaterializationArguments(
                allowsRealtimeFollow: false,
                hasTransition: false
            )
        ])
    }

    @Test("Application effects do not retain their target")
    func doesNotRetainTarget() throws {
        var target: StoreApplicationEffectTargetSpy? =
            StoreApplicationEffectTargetSpy()
        weak var weakTarget = target
        let effects = HomeStoreApplicationEffectsFactory.make(
            target: try #require(target)
        )

        target = nil

        #expect(weakTarget == nil)
        effects.materializeEntries()
    }
}

@MainActor
private func applyProjectionEffects(
    _ effects: HomeTimelineStoreApplicationEffects,
    fixture: StoreApplicationDispatcherFixture
) {
    effects.applyPresentationTransition(fixture.presentationTransition)
    effects.applyContentSnapshot(fixture.contentSnapshot)
    effects.applyRelayStatusSnapshot(fixture.relaySnapshot)
    effects.applyListProjectionInvalidation(
        HomeTimelineListProjectionInvalidation(revision: 4)
    )
    effects.applyPendingEventCountPublication(
        HomeTimelinePendingEventCountPublication(count: 3)
    )
    effects.reloadProjection(fixture.account, "anchor", true)
    effects.reloadNewestProjectionWindow(fixture.account)
    effects.requestNewestProjectionReload()
    effects.scheduleMaterialization(120, true)
    effects.materializeEntries()
}

@MainActor
private func applyRuntimeEffects(
    _ effects: HomeTimelineStoreApplicationEffects,
    fixture: StoreApplicationDispatcherFixture,
    phase: NostrHomeTimelinePhase
) {
    effects.applyRelayStatusTransition(fixture.relayTransition)
    effects.setRealtime(true)
    effects.setPhase(phase)
    effects.handleBackwardCompletion(fixture.backwardCompletion)
    effects.invalidateListEntries()
    effects.scheduleLinkPreviewResolution()
    effects.publishRelayStatusChange()
}

@MainActor
private func applyAsyncEffects(
    _ effects: HomeTimelineStoreApplicationEffects,
    fixture: StoreApplicationDispatcherFixture
) async {
    await effects.handleRuntimeEvent(
        "wss://relay.example",
        "factory-subscription",
        fixture.event
    )
    await effects.persistDatabase(fixture.account)
}

@MainActor
private func expectedProjectionEvents(
    _ fixture: StoreApplicationDispatcherFixture
) -> [StoreApplicationDispatchProbe.Event] {
    [
        .presentation(
            changes: fixture.presentationTransition.changes.rawValue
        ),
        .contentRelays(fixture.contentSnapshot.resolvedRelays),
        .relaySnapshot(
            plannedCount: fixture.relaySnapshot.plannedRelayCount
        ),
        .listRevision(4),
        .pendingCount(3),
        .reloadProjection(
            accountID: fixture.account.pubkey,
            anchorEventID: "anchor",
            mergingWithCurrentWindow: true
        ),
        .reloadNewestProjectionWindow(fixture.account.pubkey),
        .requestNewestProjectionReload,
        .scheduleMaterialization(
            delayNanoseconds: 120,
            allowsRealtimeFollow: true
        ),
        .materializeEntries
    ]
}

@MainActor
private func expectedRuntimeEvents(
    _ fixture: StoreApplicationDispatcherFixture,
    phase: NostrHomeTimelinePhase
) -> [StoreApplicationDispatchProbe.Event] {
    [
        .relayTransition(fixture.relayTransition),
        .setRealtime(true),
        .setPhase(phase),
        .backwardCompletion(fixture.backwardCompletion),
        .invalidateListEntries,
        .scheduleLinkPreviewResolution,
        .publishRelayStatusChange
    ]
}

@MainActor
private func expectedAsyncEvents(
    _ fixture: StoreApplicationDispatcherFixture
) -> [StoreApplicationDispatchProbe.Event] {
    [
        .runtimeEvent(
            relayURL: "wss://relay.example",
            subscriptionID: "factory-subscription",
            eventID: fixture.event.id
        ),
        .persistDatabase(fixture.account.pubkey)
    ]
}

private struct MaterializationArguments: Equatable {
    let allowsRealtimeFollow: Bool
    let hasTransition: Bool
}

@MainActor
private final class StoreApplicationEffectTargetSpy:
    HomeStoreApplicationEffectTarget {
    private(set) var events: [StoreApplicationDispatchProbe.Event] = []
    private(set) var receivedProjectionCompletion = false
    private(set) var materializationArguments: [MaterializationArguments] = []

    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        events.append(.presentation(changes: transition.changes.rawValue))
    }

    func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        events.append(.contentRelays(snapshot.resolvedRelays))
    }

    func applyRelayStatusSnapshot(_ snapshot: HomeTimelineRelayStatusSnapshot) {
        events.append(.relaySnapshot(plannedCount: snapshot.plannedRelayCount))
    }

    func applyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) {
        events.append(.listRevision(invalidation.revision))
    }

    func applyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    ) {
        events.append(.pendingCount(publication.count))
    }

    func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    ) {
        receivedProjectionCompletion = onCompletion != nil
        events.append(.reloadProjection(
            accountID: account.pubkey,
            anchorEventID: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow
        ))
    }

    func reloadNewestProjectionWindow(account: NostrAccount) {
        events.append(.reloadNewestProjectionWindow(account.pubkey))
    }

    func requestNewestProjectionReload() {
        events.append(.requestNewestProjectionReload)
    }

    func scheduleMaterializeEntries(
        delayNanoseconds: UInt64?,
        allowsRealtimeFollow: Bool?
    ) {
        events.append(.scheduleMaterialization(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow
        ))
    }

    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    ) {
        materializationArguments.append(MaterializationArguments(
            allowsRealtimeFollow: allowsRealtimeFollow,
            hasTransition: onTransition != nil
        ))
        events.append(.materializeEntries)
    }

    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) {
        events.append(.relayTransition(transition))
    }

    func applyActivityIntent(_ intent: HomeTimelineActivityIntent) {
        switch intent {
        case .setPhase(let phase):
            events.append(.setPhase(phase))
        case .setRealtime(let isRealtime):
            events.append(.setRealtime(isRealtime))
        }
    }

    func handleBackwardCompletion(_ completion: NostrBackwardREQCompletion) {
        events.append(.backwardCompletion(completion))
    }

    func invalidateListEntries() {
        events.append(.invalidateListEntries)
    }

    func scheduleLinkPreviewResolution() {
        events.append(.scheduleLinkPreviewResolution)
    }

    func publishRelayStatusChange() {
        events.append(.publishRelayStatusChange)
    }

    func handleRuntimeEvent(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    ) async {
        events.append(.runtimeEvent(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            eventID: event.id
        ))
    }

    func persistDatabase(account: NostrAccount) async {
        events.append(.persistDatabase(account.pubkey))
    }
}
