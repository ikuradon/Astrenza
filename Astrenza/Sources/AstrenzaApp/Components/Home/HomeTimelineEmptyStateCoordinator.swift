struct HomeTimelineEmptyStateContext {
    let interaction: HomeTimelineInteractionContext
    let phase: NostrHomeTimelinePhase
    let initialSyncState: HomeTimelineInitialSyncState
    let hasFollowedPubkeys: Bool
}

enum HomeTimelineEmptyStatePolicy {
    enum PrimaryAction: Equatable {
        case refresh
        case relayStatus
        case settings
    }

    enum SecondaryAction: Equatable {
        case explore
    }

    struct Resolution: Equatable {
        let emptyState: TimelineEmptyState
        let primaryAction: PrimaryAction
        let secondaryAction: SecondaryAction?
    }

    static func resolve(
        _ context: HomeTimelineEmptyStateContext
    ) -> Resolution {
        Resolution(
            emptyState: emptyState(for: context),
            primaryAction: primaryAction(for: context),
            secondaryAction: context.interaction.timeline == .home ?
                .explore : nil
        )
    }

    private static func emptyState(
        for context: HomeTimelineEmptyStateContext
    ) -> TimelineEmptyState {
        guard context.interaction.canMutateLiveHome else {
            return context.interaction.timeline.emptyState
        }

        switch context.phase {
        case .idle, .resolvingRelays, .resolvingContacts, .loadingHome:
            return .loadingHome(message: context.phase.copy)
        case .failed(let message):
            return .liveError(message: message)
        case .loaded:
            switch context.initialSyncState {
            case .awaitingRelayResponses:
                return .loadingHome(
                    message: "Waiting for initial responses from Home relays"
                )
            case .synchronized:
                return context.hasFollowedPubkeys ? .home : .noContacts
            case .degraded:
                return .liveError(
                    message: "Some Home relays did not complete the initial timeline request."
                )
            case .unavailable:
                return .liveError(
                    message: "Home relays did not return a complete initial timeline response."
                )
            }
        }
    }

    private static func primaryAction(
        for context: HomeTimelineEmptyStateContext
    ) -> PrimaryAction {
        if context.interaction.canMutateLiveHome {
            switch context.phase {
            case .failed:
                return .refresh
            case .loaded where context.initialSyncState == .degraded ||
                    context.initialSyncState == .unavailable:
                return .refresh
            case .loaded where context.initialSyncState == .synchronized &&
                    !context.hasFollowedPubkeys:
                return .refresh
            case .idle, .resolvingRelays, .resolvingContacts,
                    .loadingHome, .loaded:
                return .relayStatus
            }
        }

        switch context.interaction.timeline {
        case .home, .relays:
            return .relayStatus
        case .lists:
            return .settings
        }
    }
}

@MainActor
protocol HomeTimelineEmptyStateActionHandling: AnyObject {
    var phase: NostrHomeTimelinePhase { get }
    var initialHomeTimelineSyncState: HomeTimelineInitialSyncState { get }
    var hasFollowedPubkeysForEmptyState: Bool { get }

    func refresh()
}

extension NostrHomeTimelineStore: HomeTimelineEmptyStateActionHandling {
    var hasFollowedPubkeysForEmptyState: Bool {
        !followedPubkeys.isEmpty
    }
}

@MainActor
final class HomeTimelineEmptyStateActionCoordinator {
    private let actions: any HomeTimelineEmptyStateActionHandling

    init(actions: any HomeTimelineEmptyStateActionHandling) {
        self.actions = actions
    }

    func performPrimaryAction(
        interaction: HomeTimelineInteractionContext,
        presentRelayStatus: () -> Void,
        presentSettings: () -> Void
    ) {
        switch resolution(for: interaction).primaryAction {
        case .refresh:
            actions.refresh()
        case .relayStatus:
            presentRelayStatus()
        case .settings:
            presentSettings()
        }
    }

    func performSecondaryAction(
        interaction: HomeTimelineInteractionContext,
        selectExplore: () -> Void
    ) {
        switch resolution(for: interaction).secondaryAction {
        case .explore:
            selectExplore()
        case nil:
            break
        }
    }

    private func resolution(
        for interaction: HomeTimelineInteractionContext
    ) -> HomeTimelineEmptyStatePolicy.Resolution {
        guard interaction.canMutateLiveHome else {
            return HomeTimelineEmptyStatePolicy.resolve(
                HomeTimelineEmptyStateContext(
                    interaction: interaction,
                    phase: .idle,
                    initialSyncState: .awaitingRelayResponses,
                    hasFollowedPubkeys: false
                )
            )
        }
        return HomeTimelineEmptyStatePolicy.resolve(
            HomeTimelineEmptyStateContext(
                interaction: interaction,
                phase: actions.phase,
                initialSyncState: actions.initialHomeTimelineSyncState,
                hasFollowedPubkeys:
                    actions.hasFollowedPubkeysForEmptyState
            )
        )
    }
}
