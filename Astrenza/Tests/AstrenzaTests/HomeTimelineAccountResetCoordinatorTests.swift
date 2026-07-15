import Testing
@testable import Astrenza

@Suite("Home timeline account reset coordinator")
@MainActor
struct HomeTimelineAccountResetCoordinatorTests {
    @Test("Account reset preserves the complete reset and publication order")
    func resetsAccountStateInOrder() {
        let probe = HomeTimelineAccountResetProbe()
        let coordinator = HomeTimelineAccountResetCoordinator(
            dependencies: probe.dependencies
        )
        let readBoundaryWrite = HomeTimelineReadBoundaryWrite(
            scopeID: "account",
            feedID: "home",
            boundary: nil,
            updatedAt: 123
        )

        coordinator.reset(
            context: HomeTimelineAccountResetContext(
                readBoundaryWrite: readBoundaryWrite,
                resolvedRelays: probe.resolvedRelays
            ),
            handlers: probe.handlers
        )

        #expect(probe.steps == HomeTimelineAccountResetProbe.Step.expectedOrder)
        #expect(probe.readBoundaryScopeID == readBoundaryWrite.scopeID)
        #expect(probe.relayStatusResetInput == probe.resolvedRelays)
        #expect(probe.appliedPresentationChanges == probe.presentationTransition.changes)
        #expect(
            probe.appliedPresentationDidChangeReadState ==
                probe.presentationTransition.didChangeReadState
        )
        #expect(probe.appliedActivityTransition == probe.activityTransition)
        #expect(probe.appliedContentSnapshot == probe.contentSnapshot)
        #expect(probe.appliedRelayStatusSnapshot == probe.relayStatusSnapshot)
        #expect(probe.scheduledCancellationGeneration == probe.cancellationGeneration)
    }
}

@MainActor
private final class HomeTimelineAccountResetProbe {
    enum Step: Equatable {
        case endReadSession
        case flushRelayTraffic
        case cancelLifecycle
        case cancelGapReconciliation
        case cancelRuntimeEvents
        case resetLinkPreviews
        case resetPresentation
        case applyPresentationTransition
        case cancelOutbox
        case resetDependencies
        case resetBackwardRequests
        case clearPendingEvents
        case resetActivity
        case applyActivityTransition
        case invalidateListEntries
        case resetProjection
        case resetRuntimeSetup
        case resetRealtimeState
        case resetFeedSync
        case resetContent
        case applyContentSnapshot
        case resetRelayStatus
        case applyRelayStatusSnapshot
        case applyProjectionViewportTransition(
            HomeTimelineProjectionViewportTransition
        )
        case resetFilters
        case publishRelayStatusChange
        case applyAccountContextTransition(HomeTimelineAccountContextTransition)
        case scheduleRuntimeShutdown

        static let expectedOrder: [Step] = [
            .endReadSession,
            .flushRelayTraffic,
            .cancelLifecycle,
            .cancelGapReconciliation,
            .cancelRuntimeEvents,
            .resetLinkPreviews,
            .resetPresentation,
            .applyPresentationTransition,
            .cancelOutbox,
            .resetDependencies,
            .resetBackwardRequests,
            .clearPendingEvents,
            .resetActivity,
            .applyActivityTransition,
            .invalidateListEntries,
            .resetProjection,
            .resetRuntimeSetup,
            .resetRealtimeState,
            .resetFeedSync,
            .resetContent,
            .applyContentSnapshot,
            .resetRelayStatus,
            .applyRelayStatusSnapshot,
            .applyProjectionViewportTransition(.resetToNewest),
            .resetFilters,
            .publishRelayStatusChange,
            .applyAccountContextTransition(.clear),
            .scheduleRuntimeShutdown
        ]
    }

    let resolvedRelays = ["wss://relay.one", "wss://relay.two"]
    let cancellationGeneration: UInt64 = 42
    let presentationTransition = HomeTimelinePresentationTransition(
        snapshot: HomeTimelinePresentationSnapshot(
            entries: [],
            filterStatus: TimelineFilterStatus(),
            materializedUnreadCount: 0,
            visibleUnreadBadgeCount: 0,
            resolvedContentRevision: 7,
            realtimeFollowSourceRevision: nil
        ),
        changes: [.entries, .resolvedContentRevision],
        didChangeReadState: true
    )
    let activityTransition = HomeTimelineActivityTransition(
        snapshot: HomeTimelineActivitySnapshot(
            phase: .idle,
            isRefreshing: false,
            isLoadingOlder: false,
            isRealtime: false
        ),
        changes: [.phase, .realtime]
    )
    let contentSnapshot = HomeTimelineContentSnapshot.initial
    let relayStatusSnapshot = HomeTimelineRelayStatusSnapshot(
        runtimeStates: [:],
        connectedRelayCount: 0,
        plannedRelayCount: 2
    )

    private(set) var steps: [Step] = []
    private(set) var readBoundaryScopeID: String?
    private(set) var relayStatusResetInput: [String] = []
    private(set) var appliedPresentationChanges: HomeTimelinePresentationChanges?
    private(set) var appliedPresentationDidChangeReadState: Bool?
    private(set) var appliedActivityTransition: HomeTimelineActivityTransition?
    private(set) var appliedContentSnapshot: HomeTimelineContentSnapshot?
    private(set) var appliedRelayStatusSnapshot: HomeTimelineRelayStatusSnapshot?
    private(set) var scheduledCancellationGeneration: UInt64?

    var dependencies: HomeTimelineAccountResetDependencies {
        HomeTimelineAccountResetDependencies(
            endReadSession: { [self] readBoundaryWrite in
                record(.endReadSession)
                readBoundaryScopeID = readBoundaryWrite?.scopeID
            },
            flushRelayTraffic: { [self] in record(.flushRelayTraffic) },
            cancelLifecycle: { [self] in
                record(.cancelLifecycle)
                return cancellationGeneration
            },
            cancelGapReconciliation: { [self] in record(.cancelGapReconciliation) },
            cancelRuntimeEvents: { [self] in record(.cancelRuntimeEvents) },
            resetLinkPreviews: { [self] in record(.resetLinkPreviews) },
            resetPresentation: { [self] in
                record(.resetPresentation)
                return presentationTransition
            },
            cancelOutbox: { [self] in record(.cancelOutbox) },
            resetDependencies: { [self] in record(.resetDependencies) },
            resetBackwardRequests: { [self] in record(.resetBackwardRequests) },
            resetActivity: { [self] in
                record(.resetActivity)
                return activityTransition
            },
            resetProjection: { [self] in record(.resetProjection) },
            resetRuntimeSetup: { [self] in record(.resetRuntimeSetup) },
            resetFeedSync: { [self] in record(.resetFeedSync) },
            resetContent: { [self] in
                record(.resetContent)
                return contentSnapshot
            },
            resetRelayStatus: { [self] resolvedRelays in
                record(.resetRelayStatus)
                relayStatusResetInput = resolvedRelays
                return relayStatusSnapshot
            },
            resetFilters: { [self] in record(.resetFilters) }
        )
    }

    var handlers: HomeTimelineAccountResetHandlers {
        HomeTimelineAccountResetHandlers(
            applyPresentationTransition: { [self] transition in
                record(.applyPresentationTransition)
                appliedPresentationChanges = transition.changes
                appliedPresentationDidChangeReadState = transition.didChangeReadState
            },
            clearPendingEvents: { [self] in record(.clearPendingEvents) },
            applyActivityTransition: { [self] transition in
                record(.applyActivityTransition)
                appliedActivityTransition = transition
            },
            invalidateListEntries: { [self] in record(.invalidateListEntries) },
            resetRealtimeState: { [self] in record(.resetRealtimeState) },
            applyContentSnapshot: { [self] snapshot in
                record(.applyContentSnapshot)
                appliedContentSnapshot = snapshot
            },
            applyRelayStatusSnapshot: { [self] snapshot in
                record(.applyRelayStatusSnapshot)
                appliedRelayStatusSnapshot = snapshot
            },
            applyProjectionViewportTransition: { [self] transition in
                record(.applyProjectionViewportTransition(transition))
            },
            publishRelayStatusChange: { [self] in
                record(.publishRelayStatusChange)
            },
            applyAccountContextTransition: { [self] transition in
                record(.applyAccountContextTransition(transition))
            },
            scheduleRuntimeShutdown: { [self] cancellationGeneration in
                record(.scheduleRuntimeShutdown)
                scheduledCancellationGeneration = cancellationGeneration
            }
        )
    }

    private func record(_ step: Step) {
        steps.append(step)
    }
}
