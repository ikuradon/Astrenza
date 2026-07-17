import Foundation

enum NostrHomeTimelinePhase: Equatable, Sendable {
    case idle
    case resolvingRelays
    case resolvingContacts
    case loadingHome
    case loaded
    case failed(String)

    var copy: String {
        switch self {
        case .idle:
            "Preparing Home timeline"
        case .resolvingRelays:
            "Resolving kind:10002 relay list"
        case .resolvingContacts:
            "Resolving kind:3 contact list"
        case .loadingHome:
            "Connecting Home relays"
        case .loaded:
            "Home timeline loaded"
        case .failed(let message):
            message
        }
    }
}

struct NostrTimelineActivityStatus: Equatable, Sendable {
    let title: String
    let detail: String
    let compactLabel: String
}

struct HomeTimelineActivityContext: Equatable, Sendable {
    let connectedRelayCount: Int
    let plannedRelayCount: Int
    let initialSyncState: HomeTimelineInitialSyncState
    let hasOlderPageRequest: Bool
    let hasGapWork: Bool
    let hasBackwardRequests: Bool
    let hasPendingDependencyWork: Bool
}

struct HomeTimelineActivitySnapshot: Equatable, Sendable {
    let phase: NostrHomeTimelinePhase
    let isRefreshing: Bool
    let isLoadingOlder: Bool
    let isRealtime: Bool
}

struct HomeTimelineActivityChanges: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let phase = HomeTimelineActivityChanges(rawValue: 1 << 0)
    static let refreshing = HomeTimelineActivityChanges(rawValue: 1 << 1)
    static let loadingOlder = HomeTimelineActivityChanges(rawValue: 1 << 2)
    static let realtime = HomeTimelineActivityChanges(rawValue: 1 << 3)
}

struct HomeTimelineActivityTransition: Equatable, Sendable {
    let snapshot: HomeTimelineActivitySnapshot
    let changes: HomeTimelineActivityChanges
}

@MainActor
final class HomeTimelineActivityCoordinator {
    private var phase: NostrHomeTimelinePhase = .idle
    private var isRefreshing = false
    private var isLoadingOlder = false
    private var isRealtime = false

    var snapshot: HomeTimelineActivitySnapshot {
        HomeTimelineActivitySnapshot(
            phase: phase,
            isRefreshing: isRefreshing,
            isLoadingOlder: isLoadingOlder,
            isRealtime: isRealtime
        )
    }

    var canBeginRefresh: Bool {
        !isRefreshing
    }

    var canBeginLoadingOlder: Bool {
        !isLoadingOlder
    }

    func reset() -> HomeTimelineActivityTransition {
        let previous = snapshot
        phase = .idle
        isRefreshing = false
        isLoadingOlder = false
        isRealtime = false
        return transition(from: previous)
    }

    func setPhase(_ phase: NostrHomeTimelinePhase) -> HomeTimelineActivityTransition {
        let previous = snapshot
        self.phase = phase
        return transition(from: previous)
    }

    func beginRefresh() -> HomeTimelineActivityTransition? {
        guard canBeginRefresh else { return nil }
        let previous = snapshot
        isRefreshing = true
        return transition(from: previous)
    }

    func endRefresh() -> HomeTimelineActivityTransition {
        let previous = snapshot
        isRefreshing = false
        return transition(from: previous)
    }

    func beginLoadingOlder() -> HomeTimelineActivityTransition? {
        guard canBeginLoadingOlder else { return nil }
        let previous = snapshot
        isLoadingOlder = true
        return transition(from: previous)
    }

    func endLoadingOlder() -> HomeTimelineActivityTransition {
        let previous = snapshot
        isLoadingOlder = false
        return transition(from: previous)
    }

    func setRealtime(_ isRealtime: Bool) -> HomeTimelineActivityTransition {
        let previous = snapshot
        self.isRealtime = isRealtime
        return transition(from: previous)
    }

    func activityStatus(context: HomeTimelineActivityContext) -> NostrTimelineActivityStatus? {
        switch phase {
        case .resolvingRelays:
            return NostrTimelineActivityStatus(
                title: "Resolving relay list",
                detail: "Looking up kind:10002 on discovery relays",
                compactLabel: "kind:10002"
            )
        case .resolvingContacts:
            return NostrTimelineActivityStatus(
                title: "Resolving contacts",
                detail: "Looking up kind:3 before opening Home",
                compactLabel: "kind:3"
            )
        case .loadingHome:
            return NostrTimelineActivityStatus(
                title: "Connecting Home relays",
                detail: "\(context.connectedRelayCount) of \(context.plannedRelayCount) relays ready",
                compactLabel: "Home"
            )
        case .idle, .loaded, .failed:
            break
        }

        if isRefreshing {
            return NostrTimelineActivityStatus(
                title: "Updating Home timeline",
                detail: "Fetching newer events from Home relays",
                compactLabel: "Updating"
            )
        }
        if isLoadingOlder || context.hasOlderPageRequest {
            return NostrTimelineActivityStatus(
                title: "Loading older posts",
                detail: "Fetching the previous Home timeline window",
                compactLabel: "Older"
            )
        }
        if context.hasGapWork {
            return NostrTimelineActivityStatus(
                title: "Filling a timeline gap",
                detail: "Reconciling missing events between local windows",
                compactLabel: "Gap"
            )
        }
        if phase == .loaded,
           context.initialSyncState == .awaitingRelayResponses {
            return NostrTimelineActivityStatus(
                title: "Synchronizing Home timeline",
                detail: "\(context.connectedRelayCount) of \(context.plannedRelayCount) relays connected; waiting for initial EOSE",
                compactLabel: "Syncing"
            )
        }
        if context.hasBackwardRequests || context.hasPendingDependencyWork {
            return NostrTimelineActivityStatus(
                title: "Resolving referenced posts",
                detail: "Fetching events referenced by visible posts",
                compactLabel: "Resolving"
            )
        }
        return nil
    }

    private func transition(
        from previous: HomeTimelineActivitySnapshot
    ) -> HomeTimelineActivityTransition {
        let next = snapshot
        var changes: HomeTimelineActivityChanges = []
        if previous.phase != next.phase {
            changes.insert(.phase)
        }
        if previous.isRefreshing != next.isRefreshing {
            changes.insert(.refreshing)
        }
        if previous.isLoadingOlder != next.isLoadingOlder {
            changes.insert(.loadingOlder)
        }
        if previous.isRealtime != next.isRealtime {
            changes.insert(.realtime)
        }
        return HomeTimelineActivityTransition(snapshot: next, changes: changes)
    }
}
