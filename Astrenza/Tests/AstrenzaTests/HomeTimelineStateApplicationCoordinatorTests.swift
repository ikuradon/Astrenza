import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline state application coordinator")
@MainActor
struct HomeTimelineStateApplicationTests {
    @Test("Cached state is restored through the shared replacement transaction")
    func cachedStateUsesSharedReplacementTransaction() {
        let state = timelineState(relays: ["wss://incoming.example"])
        let probe = Probe(cachedState: state)
        let coordinator = HomeTimelineStateApplicationCoordinator(
            dependencies: probe.dependencies()
        )

        let didRestore = coordinator.restoreCachedState(
            accountID: "account",
            handlers: probe.handlers()
        )

        #expect(didRestore)
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
    func missingCacheResetsCachedStateSurfaces() {
        let probe = Probe(
            cachedState: nil,
            resetContentRelays: ["wss://reset-effective.example"]
        )
        let coordinator = HomeTimelineStateApplicationCoordinator(
            dependencies: probe.dependencies()
        )

        let didRestore = coordinator.restoreCachedState(
            accountID: "account",
            handlers: probe.handlers()
        )

        #expect(!didRestore)
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
            .pendingCountChanged(0)
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
        case pendingCountChanged(Int)
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

    func dependencies() -> HomeTimelineStateApplicationDependencies {
        HomeTimelineStateApplicationDependencies(
            restoredState: { [self] accountID in
                events.append(.restoreState(accountID))
                return cachedState
            },
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
            clearPendingEvents: { [self] onCountChange in
                events.append(.clearPendingEvents)
                onCountChange(0)
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
            pendingCountChanged: { [self] count in
                events.append(.pendingCountChanged(count))
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
