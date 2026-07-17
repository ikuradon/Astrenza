import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline state application coordinator")
@MainActor
struct HomeTimelineStateApplicationTests {
    @Test("Cached state is restored through the shared replacement transaction")
    func cachedStateUsesSharedReplacementTransaction() async {
        let state = timelineState(relays: ["wss://incoming.example"])
        let probe = Probe(cachedState: state)
        let coordinator = HomeTimelineStateApplicationCoordinator(
            dependencies: probe.dependencies()
        )

        let outcome = await coordinator.restoreCachedState(
            accountID: "account",
            handlers: probe.handlers()
        )

        #expect(outcome == .restored(state))
        #expect(probe.events == [
            .restoreState("account"),
            .replaceContent("account"),
            .applyContent(["wss://effective.example"]),
            .replaceNIP05Resolutions(0),
            .replaceRelayEvents(
                eventCount: 0,
                relays: ["wss://effective.example"]
            ),
            .applyRelayStatus(plannedRelayCount: 1),
            .clearProjectionWindow,
            .invalidateListProjection,
            .applyListProjectionInvalidation(41)
        ])
    }

    @Test("Missing cache resets only the stale presentation and cached state surfaces")
    func missingCacheResetsCachedStateSurfaces() async {
        let probe = Probe(
            cachedState: nil,
            resetContentRelays: ["wss://reset-effective.example"]
        )
        let coordinator = HomeTimelineStateApplicationCoordinator(
            dependencies: probe.dependencies()
        )

        let outcome = await coordinator.restoreCachedState(
            accountID: "account",
            handlers: probe.handlers()
        )

        #expect(outcome == .missing)
        #expect(probe.events == [
            .restoreState("account"),
            .resetPresentation,
            .applyPresentation,
            .resetContent,
            .applyContent(["wss://reset-effective.example"]),
            .replaceNIP05Resolutions(0),
            .resetRelayStatus(["wss://reset-effective.example"]),
            .applyRelayStatus(plannedRelayCount: 1),
            .clearPendingEvents,
            .applyPendingEventCountPublication(0)
        ])
    }

    @Test("Direct replacement does not read cache and preserves a missing account context")
    func directReplacementDoesNotReadCache() {
        let probe = Probe(cachedState: timelineState(relays: []))
        let coordinator = HomeTimelineStateApplicationCoordinator(
            dependencies: probe.dependencies()
        )

        coordinator.replace(
            timelineState(relays: ["wss://incoming.example"]),
            accountID: nil,
            handlers: probe.handlers()
        )

        #expect(probe.events == [
            .replaceContent(nil),
            .applyContent(["wss://effective.example"]),
            .replaceNIP05Resolutions(0),
            .replaceRelayEvents(
                eventCount: 0,
                relays: ["wss://effective.example"]
            ),
            .applyRelayStatus(plannedRelayCount: 1),
            .clearProjectionWindow,
            .invalidateListProjection,
            .applyListProjectionInvalidation(41)
        ])
    }

    @Test("A canceled cache read cannot apply stale state")
    func canceledCacheReadDoesNotApplyState() async {
        let state = timelineState(relays: ["wss://stale.example"])
        let gate = HomeTimelineCachedStateRestoreGate()
        let probe = Probe(cachedState: nil)
        let coordinator = HomeTimelineStateApplicationCoordinator(
            dependencies: probe.dependencies(restoredState: { _ in
                await gate.suspend()
                return .restored(state)
            })
        )

        let restoreTask = Task { @MainActor in
            await coordinator.restoreCachedState(
                accountID: "stale-account",
                handlers: probe.handlers()
            )
        }
        await gate.waitUntilSuspended()
        restoreTask.cancel()
        await gate.resume()

        #expect(await restoreTask.value == .cancelled)
        #expect(probe.events.isEmpty)
    }

    @Test("A failed cache read preserves the current presentation")
    func failedCacheReadPreservesCurrentPresentation() async {
        let probe = Probe(cachedState: nil)
        let coordinator = HomeTimelineStateApplicationCoordinator(
            dependencies: probe.dependencies(restoredState: { _ in
                .failed("Database restore failed: corrupt")
            })
        )

        let outcome = await coordinator.restoreCachedState(
            accountID: "account",
            handlers: probe.handlers()
        )

        #expect(outcome == .failed("Database restore failed: corrupt"))
        #expect(probe.events.isEmpty)
    }

    private func timelineState(relays: [String]) -> NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: relays,
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: [],
            nip05Resolutions: [:],
            hasMoreOlder: true,
            relaySyncEvents: []
        )
    }
}

@MainActor
private final class Probe {
    enum Event: Equatable {
        case restoreState(String)
        case resetPresentation
        case applyPresentation
        case replaceContent(String?)
        case resetContent
        case applyContent([String])
        case replaceNIP05Resolutions(Int)
        case replaceRelayEvents(eventCount: Int, relays: [String])
        case resetRelayStatus([String])
        case applyRelayStatus(plannedRelayCount: Int)
        case clearProjectionWindow
        case invalidateListProjection
        case applyListProjectionInvalidation(Int)
        case clearPendingEvents
        case applyPendingEventCountPublication(Int)
    }

    private let cachedState: NostrHomeTimelineState?
    private let resetContentRelays: [String]
    private let presentationCoordinator = HomeTimelinePresentationCoordinator()
    private(set) var events: [Event] = []

    init(
        cachedState: NostrHomeTimelineState?,
        resetContentRelays: [String] = []
    ) {
        self.cachedState = cachedState
        self.resetContentRelays = resetContentRelays
    }

    func dependencies(
        restoredState: HomeTimelineStateApplicationDependencies.StateRestorer? = nil
    ) -> HomeTimelineStateApplicationDependencies {
        let restore = restoredState ?? { [self] accountID in
            events.append(.restoreState(accountID))
            return cachedState.map {
                HomeTimelineCachedStateRestoreOutcome.restored($0)
            } ?? .missing
        }
        return HomeTimelineStateApplicationDependencies(
            restoredState: restore,
            resetPresentation: { [self] in
                events.append(.resetPresentation)
                return presentationCoordinator.reset()
            },
            replaceContent: { [self] _, accountID in
                events.append(.replaceContent(accountID))
                return contentSnapshot(relays: ["wss://effective.example"])
            },
            resetContent: { [self] in
                events.append(.resetContent)
                return contentSnapshot(relays: resetContentRelays)
            },
            replaceNIP05Resolutions: { [self] resolutions in
                events.append(.replaceNIP05Resolutions(resolutions.count))
            },
            replaceRelayEvents: { [self] relayEvents, relays in
                events.append(.replaceRelayEvents(
                    eventCount: relayEvents.count,
                    relays: relays
                ))
                return relayStatusSnapshot(relays: relays)
            },
            resetRelayStatus: { [self] relays in
                events.append(.resetRelayStatus(relays))
                return relayStatusSnapshot(relays: relays)
            },
            clearProjectionWindow: { [self] in
                events.append(.clearProjectionWindow)
            },
            invalidateListProjection: { [self] in
                events.append(.invalidateListProjection)
                return HomeTimelineListProjectionInvalidation(revision: 41)
            },
            clearPendingEvents: { [self] onCountPublication in
                events.append(.clearPendingEvents)
                onCountPublication(
                    HomeTimelinePendingEventCountPublication(count: 0)
                )
            }
        )
    }

    func handlers() -> HomeTimelineStateApplicationHandlers {
        HomeTimelineStateApplicationHandlers(
            applyPresentationTransition: { [self] _ in
                events.append(.applyPresentation)
            },
            applyContentSnapshot: { [self] snapshot in
                events.append(.applyContent(snapshot.resolvedRelays))
            },
            applyRelayStatusSnapshot: { [self] snapshot in
                events.append(.applyRelayStatus(
                    plannedRelayCount: snapshot.plannedRelayCount
                ))
            },
            applyListProjectionInvalidation: { [self] invalidation in
                events.append(.applyListProjectionInvalidation(
                    invalidation.revision
                ))
            },
            applyPendingEventCountPublication: { [self] publication in
                events.append(.applyPendingEventCountPublication(
                    publication.count
                ))
            }
        )
    }

    private func contentSnapshot(relays: [String]) -> HomeTimelineContentSnapshot {
        HomeTimelineContentSnapshot(
            resolvedRelays: relays,
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: true
        )
    }

    private func relayStatusSnapshot(
        relays: [String]
    ) -> HomeTimelineRelayStatusSnapshot {
        HomeTimelineRelayStatusSnapshot(
            runtimeStates: [:],
            connectedRelayCount: 0,
            plannedRelayCount: relays.count
        )
    }
}

private actor HomeTimelineCachedStateRestoreGate {
    private var didSuspend = false
    private var suspendedWaiter: CheckedContinuation<Void, Never>?
    private var resumeWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        didSuspend = true
        suspendedWaiter?.resume()
        suspendedWaiter = nil
        await withCheckedContinuation { continuation in
            resumeWaiter = continuation
        }
    }

    func waitUntilSuspended() async {
        guard !didSuspend else { return }
        await withCheckedContinuation { continuation in
            suspendedWaiter = continuation
        }
    }

    func resume() {
        resumeWaiter?.resume()
        resumeWaiter = nil
    }
}
