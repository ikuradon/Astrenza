import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline sync interaction workflow")
@MainActor
struct HomeTimelineSyncInteractionTests {
    @Test("Preparing subscriptions publishes state after replacing expectations")
    func preparePublishesCurrentStateAfterMutation() {
        let fixture = SyncInteractionFixture(isRealtime: false)
        let subscriptions = Set([fixture.homeKey, fixture.secondHomeKey])

        fixture.workflow.prepareForwardSubscriptions(
            subscriptions,
            context: fixture.context
        )

        #expect(fixture.tracker.events == [
            .prepare(subscriptions),
            .readRealtime
        ])
        #expect(fixture.probe.actions == [.setRealtime(false)])
    }

    @Test("Invalidating a home subscription republishes the current state")
    func homeInvalidationPublishesCurrentState() {
        let fixture = SyncInteractionFixture(isRealtime: false)

        fixture.workflow.invalidateForwardSubscription(
            fixture.homeKey,
            context: fixture.context
        )

        #expect(fixture.tracker.events == [
            .invalidate(fixture.homeKey),
            .readRealtime
        ])
        #expect(fixture.probe.actions == [.setRealtime(false)])
    }

    @Test("A non-home subscription does not mutate or publish realtime state")
    func nonHomeInvalidationIsNoOp() {
        let fixture = SyncInteractionFixture(isRealtime: true)
        let unrelatedKey = RuntimeSubscriptionKey(
            relayURL: "wss://relay.example",
            subscriptionID: "astrenza-profile-metadata"
        )

        fixture.workflow.invalidateForwardSubscription(
            unrelatedKey,
            context: fixture.context
        )

        #expect(fixture.tracker.events.isEmpty)
        #expect(fixture.probe.actions.isEmpty)
    }

    @Test("Relay invalidation republishes state after invalidating every relay key")
    func relayInvalidationPublishesCurrentState() {
        let fixture = SyncInteractionFixture(isRealtime: false)

        fixture.workflow.invalidateForwardSubscriptions(
            relayURL: fixture.homeKey.relayURL,
            context: fixture.context
        )

        #expect(fixture.tracker.events == [
            .invalidateRelay(fixture.homeKey.relayURL),
            .readRealtime
        ])
        #expect(fixture.probe.actions == [.setRealtime(false)])
    }

    @Test("Forward context registration and active metrics stay behind the facade")
    func routesRegistrationAndMetrics() throws {
        let fixture = SyncInteractionFixture(
            isRealtime: false,
            activeRequestCount: 3,
            activeContextCount: 2
        )
        let context = HomeFeedRuntimeContext(
            definition: try fixture.feedDefinition()
        )

        fixture.workflow.registerForwardContext(
            context,
            groupID: "home-forward-group"
        )

        #expect(fixture.tracker.events == [
            .register(context, groupID: "home-forward-group")
        ])
        #expect(fixture.workflow.activeRequestCount == 3)
        #expect(fixture.workflow.activeContextCount == 2)
    }

    @Test("Backward request state and registrations stay behind the facade")
    func routesBackwardRequestStateAndRegistrations() throws {
        let requestState = HomeTimelineBackwardRequestState(
            requestCount: 3,
            hasOlderPageRequest: true,
            hasGapWork: true,
            hasRequests: true
        )
        let fixture = SyncInteractionFixture(
            isRealtime: false,
            backwardRequestState: requestState
        )
        let context = HomeFeedRuntimeContext(
            definition: try fixture.feedDefinition()
        )

        fixture.workflow.registerOlderPage(
            groupID: "older-group",
            context: context,
            anchorEventID: "anchor"
        )
        fixture.workflow.registerGap(
            groupID: "gap-group",
            context: context,
            newerEventID: "newer",
            olderEventID: "older",
            direction: .newer
        )

        #expect(fixture.workflow.backwardRequestState == requestState)
        #expect(fixture.backwardRequests.events == [
            .registerOlderPage(
                groupID: "older-group",
                context: context,
                anchorEventID: "anchor"
            ),
            .registerGap(
                groupID: "gap-group",
                context: context,
                newerEventID: "newer",
                olderEventID: "older",
                direction: .newer
            )
        ])
    }
}

private enum FeedSyncInteractionEvent: Equatable {
    case prepare(Set<RuntimeSubscriptionKey>)
    case invalidate(RuntimeSubscriptionKey)
    case invalidateRelay(String)
    case register(HomeFeedRuntimeContext, groupID: String)
    case readRealtime
}

@MainActor
private final class FeedSyncInteractionTrackerSpy:
    HomeTimelineFeedSyncTracking {
    let activeRequestCount: Int
    let activeContextCount: Int
    private let realtime: Bool
    private(set) var events: [FeedSyncInteractionEvent] = []

    init(
        isRealtime: Bool,
        activeRequestCount: Int,
        activeContextCount: Int
    ) {
        realtime = isRealtime
        self.activeRequestCount = activeRequestCount
        self.activeContextCount = activeContextCount
    }

    var isRealtime: Bool {
        events.append(.readRealtime)
        return realtime
    }

    let initialSyncState = HomeTimelineInitialSyncState.synchronized
    let initialSyncProgress = HomeTimelineInitialSyncProgress(
        expectedRelayCount: 1,
        completedRelayCount: 1,
        successfulRelayCount: 1,
        failedRelayCount: 0
    )

    func prepareForwardSubscriptions(
        _ subscriptions: Set<RuntimeSubscriptionKey>
    ) {
        events.append(.prepare(subscriptions))
    }

    func invalidateForwardSubscription(_ key: RuntimeSubscriptionKey) {
        events.append(.invalidate(key))
    }

    func invalidateForwardSubscriptions(relayURL: String) {
        events.append(.invalidateRelay(relayURL))
    }

    func registerForwardContext(
        _ context: HomeFeedRuntimeContext,
        groupID: String
    ) {
        events.append(.register(context, groupID: groupID))
    }
}

private enum BackwardRequestInteractionEvent: Equatable {
    case registerOlderPage(
        groupID: String,
        context: HomeFeedRuntimeContext,
        anchorEventID: String?
    )
    case registerGap(
        groupID: String,
        context: HomeFeedRuntimeContext,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    )
}

@MainActor
private final class BackwardRequestInteractionTrackerSpy:
    HomeTimelineBackwardRequestTracking {
    let requestState: HomeTimelineBackwardRequestState
    private(set) var events: [BackwardRequestInteractionEvent] = []

    init(requestState: HomeTimelineBackwardRequestState) {
        self.requestState = requestState
    }

    func registerOlderPage(
        groupID: String,
        context: HomeFeedRuntimeContext,
        anchorEventID: String?
    ) {
        events.append(.registerOlderPage(
            groupID: groupID,
            context: context,
            anchorEventID: anchorEventID
        ))
    }

    func registerGap(
        groupID: String,
        context: HomeFeedRuntimeContext,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    ) {
        events.append(.registerGap(
            groupID: groupID,
            context: context,
            newerEventID: newerEventID,
            olderEventID: olderEventID,
            direction: direction
        ))
    }
}

@MainActor
private final class FeedSyncInteractionProbe {
    private(set) var actions: [HomeTimelineSyncStoreAction] = []

    var effects: HomeTimelineSyncInteractionEffects {
        HomeTimelineSyncInteractionEffects(
            apply: { [self] action in
                actions.append(action)
            }
        )
    }
}

@MainActor
private struct SyncInteractionFixture {
    let homeKey = RuntimeSubscriptionKey(
        relayURL: "wss://one.example",
        subscriptionID: NostrHomeForwardREQBuilder.subscriptionID + "-one"
    )
    let secondHomeKey = RuntimeSubscriptionKey(
        relayURL: "wss://two.example",
        subscriptionID: NostrHomeForwardREQBuilder.subscriptionID + "-two"
    )
    let tracker: FeedSyncInteractionTrackerSpy
    let backwardRequests: BackwardRequestInteractionTrackerSpy
    let probe = FeedSyncInteractionProbe()
    let workflow: HomeTimelineSyncInteractionWorkflow

    init(
        isRealtime: Bool,
        activeRequestCount: Int = 0,
        activeContextCount: Int = 0,
        backwardRequestState: HomeTimelineBackwardRequestState = .idle
    ) {
        let tracker = FeedSyncInteractionTrackerSpy(
            isRealtime: isRealtime,
            activeRequestCount: activeRequestCount,
            activeContextCount: activeContextCount
        )
        let backwardRequests = BackwardRequestInteractionTrackerSpy(
            requestState: backwardRequestState
        )
        let relayStatus = SyncInteractionRelayStatusSpy()
        self.tracker = tracker
        self.backwardRequests = backwardRequests
        workflow = HomeTimelineSyncInteractionWorkflow(
            feedSync: tracker,
            backwardRequests: backwardRequests,
            relayStatus: relayStatus
        )
    }

    var context: HomeTimelineSyncInteractionContext {
        HomeTimelineSyncInteractionContext(effects: probe.effects)
    }

    func feedDefinition() throws -> NostrFeedDefinitionRecord {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: ["author"], kinds: [1])
        )
        return NostrFeedDefinitionRecord(
            feedID: "feed:home:account",
            accountID: "account",
            kind: "home",
            specificationJSON: specification,
            specificationHash: "hash",
            revision: 1,
            createdAt: 1,
            updatedAt: 1
        )
    }
}
