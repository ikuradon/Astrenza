import AstrenzaCore
import Testing
@testable import Astrenza

enum ProjectionAnchorScenario: CaseIterable, Sendable {
    case clearWithAccount
    case restoreWithAccount
    case clearWithoutAccount
    case restoreWithoutAccount

    var anchorEventID: String? {
        switch self {
        case .clearWithAccount, .clearWithoutAccount:
            nil
        case .restoreWithAccount, .restoreWithoutAccount:
            "anchor"
        }
    }

    var hasAccount: Bool {
        self == .clearWithAccount || self == .restoreWithAccount
    }

    @MainActor
    func expectedEvents(account: NostrAccount) -> [PresentationProbe.Event] {
        switch self {
        case .clearWithAccount:
            [
                .applyProjectionViewportTransition(.setRestoreAnchor(nil)),
                .reloadNewestProjectionWindow(account),
                .materializeEntries(false)
            ]
        case .restoreWithAccount:
            [
                .applyProjectionViewportTransition(.setRestoreAnchor("anchor")),
                .applyRestoreProjectionAnchor(account)
            ]
        case .clearWithoutAccount:
            [.applyProjectionViewportTransition(.setRestoreAnchor(nil))]
        case .restoreWithoutAccount:
            [.applyProjectionViewportTransition(.setRestoreAnchor("anchor"))]
        }
    }
}

extension ProjectionAnchorScenario: CustomTestStringConvertible {
    var testDescription: String {
        switch self {
        case .clearWithAccount:
            "clear with account"
        case .restoreWithAccount:
            "restore with account"
        case .clearWithoutAccount:
            "clear without account"
        case .restoreWithoutAccount:
            "restore without account"
        }
    }
}

enum NewestWindowScenario: CaseIterable, Sendable {
    case enterWithoutAnchor
    case enterWithAnchor
    case leaveWithAnchor

    var requestedValue: Bool {
        self != .leaveWithAnchor
    }

    var anchorEventID: String? {
        self == .enterWithoutAnchor ? nil : "anchor"
    }

    @MainActor
    var expectedEvents: [PresentationProbe.Event] {
        switch self {
        case .enterWithoutAnchor:
            [.applyProjectionViewportTransition(.setNewestWindow(true))]
        case .enterWithAnchor:
            []
        case .leaveWithAnchor:
            [.applyProjectionViewportTransition(.setNewestWindow(false))]
        }
    }
}

extension NewestWindowScenario: CustomTestStringConvertible {
    var testDescription: String {
        switch self {
        case .enterWithoutAnchor:
            "enter without anchor"
        case .enterWithAnchor:
            "enter with anchor"
        case .leaveWithAnchor:
            "leave with anchor"
        }
    }
}

@MainActor
struct PresentationFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "presentation",
        readOnly: true
    )
    let feedID = "home-feed"
    let probe: PresentationProbe
    let workflow: HomeTimelinePresentationWorkflow

    init() {
        let probe = PresentationProbe()
        self.probe = probe
        workflow = HomeTimelinePresentationWorkflow(
            coordinator: probe
        )
    }

    var state: HomeTimelinePresentationAppState {
        state(account: account)
    }

    var effects: HomeTimelinePresentationEffects {
        probe.effects
    }

    func state(
        account: NostrAccount?,
        anchorEventID: String? = nil
    ) -> HomeTimelinePresentationAppState {
        HomeTimelinePresentationAppState(
            account: account,
            restoreProjectionAnchorEventID: anchorEventID
        )
    }

}

@MainActor
final class PresentationProbe: HomeTimelinePresentationCoordinating {
    enum Event: Equatable {
        case applyProjectionViewportTransition(
            HomeTimelineProjectionViewportTransition
        )
        case reloadNewestProjectionWindow(NostrAccount)
        case materializeEntries(Bool)
        case applyRestoreProjectionAnchor(NostrAccount)
        case setScrollActive(Bool)
        case dismissUnreadBadge
        case markVisiblePostsRead([TimelinePost.ID])
        case markNewestWindowRead
        case requestNewestProjectionReload
        case clearNewestProjectionReload
        case restoreReadBoundary(TimelinePost.ID)
        case scheduleMaterialization(UInt64?, Bool?)
        case replaceEntriesForTesting([TimelineFeedEntry.ID])
        case setReadBoundaryForTesting(TimelinePost.ID)
        case applyPresentationTransition(HomeTimelinePresentationChanges, Bool)
        case scheduleReadStateSave
    }

    var scrollMaterializationPermission: Bool?
    var scheduledMaterializationPermission: Bool?
    var visibleReadTransition: HomeTimelinePresentationTransition?
    var newestReadTransition: HomeTimelinePresentationTransition?
    var defaultDelayNanoseconds: UInt64 = 16_000_000
    var hasPendingNewestProjectionReload = false
    var readBoundaryPostID: TimelinePost.ID?
    private(set) var events: [Event] = []

    var effects: HomeTimelinePresentationEffects {
        HomeTimelinePresentationEffects(
            applyProjectionViewportTransition: { [self] transition in
                events.append(.applyProjectionViewportTransition(transition))
            },
            reloadNewestProjectionWindow: { [self] account in
                events.append(.reloadNewestProjectionWindow(account))
            },
            materializeEntries: { [self] allowsRealtimeFollow in
                events.append(.materializeEntries(allowsRealtimeFollow))
            },
            applyRestoreProjectionAnchor: { [self] account in
                events.append(.applyRestoreProjectionAnchor(account))
            },
            applyPresentationTransition: { [self] transition in
                events.append(.applyPresentationTransition(
                    transition.changes,
                    transition.didChangeReadState
                ))
            },
            scheduleReadStateSave: { [self] in
                events.append(.scheduleReadStateSave)
            }
        )
    }

    func setScrollActive(
        _ isActive: Bool,
        materialize: @escaping MaterializeHandler
    ) {
        events.append(.setScrollActive(isActive))
        if let scrollMaterializationPermission {
            materialize(scrollMaterializationPermission)
        }
    }

    func dismissUnreadBadge() -> HomeTimelinePresentationTransition {
        events.append(.dismissUnreadBadge)
        return presentationTransition(changes: [.unreadCounts])
    }

    func markVisiblePostsRead(
        _ visiblePostIDs: [TimelinePost.ID]
    ) -> HomeTimelinePresentationTransition? {
        events.append(.markVisiblePostsRead(visiblePostIDs))
        return visibleReadTransition
    }

    func markNewestWindowRead() -> HomeTimelinePresentationTransition? {
        events.append(.markNewestWindowRead)
        return newestReadTransition
    }

    func requestNewestProjectionReload() {
        events.append(.requestNewestProjectionReload)
    }

    func clearNewestProjectionReload() {
        events.append(.clearNewestProjectionReload)
    }

    func restoreReadBoundary(
        postID: TimelinePost.ID
    ) -> HomeTimelinePresentationTransition {
        events.append(.restoreReadBoundary(postID))
        return presentationTransition(changes: [.unreadCounts])
    }

    func schedule(
        delayNanoseconds: UInt64?,
        allowsRealtimeFollow: Bool?,
        materialize: @escaping MaterializeHandler
    ) {
        events.append(.scheduleMaterialization(
            delayNanoseconds,
            allowsRealtimeFollow
        ))
        if let scheduledMaterializationPermission {
            materialize(scheduledMaterializationPermission)
        }
    }

    #if DEBUG
    func replaceEntriesForTesting(
        _ entries: [TimelineFeedEntry],
        renderFingerprint: [Int]
    ) -> HomeTimelinePresentationTransition {
        events.append(.replaceEntriesForTesting(entries.map(\.id)))
        return presentationTransition(changes: [.entries])
    }

    func setReadBoundaryForTesting(
        postID: TimelinePost.ID
    ) -> HomeTimelinePresentationTransition {
        events.append(.setReadBoundaryForTesting(postID))
        return presentationTransition(changes: [.unreadCounts])
    }
    #endif
}

@MainActor
func presentationTransition(
    changes: HomeTimelinePresentationChanges,
    didChangeReadState: Bool = false
) -> HomeTimelinePresentationTransition {
    HomeTimelinePresentationTransition(
        snapshot: HomeTimelinePresentationSnapshot(
            entries: [],
            filterStatus: TimelineFilterStatus(),
            materializedUnreadCount: 0,
            visibleUnreadBadgeCount: 0,
            resolvedContentRevision: 0,
            realtimeFollowSourceRevision: nil
        ),
        changes: changes,
        didChangeReadState: didChangeReadState
    )
}
