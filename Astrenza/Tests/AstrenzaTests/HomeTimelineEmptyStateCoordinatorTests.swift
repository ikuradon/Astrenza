import Testing
@testable import Astrenza

@Suite("Home timeline empty-state coordinator")
@MainActor
struct HomeEmptyStateActionCoordinatorTests {
    @Test("Loading phases use progress presentation and relay status")
    func loadingPhasesUseRelayStatus() {
        for phase in [
            NostrHomeTimelinePhase.resolvingRelays,
            .resolvingContacts,
            .loadingHome
        ] {
            let resolution = resolve(phase: phase, hasFollows: false)

            #expect(resolution.emptyState == .loadingHome(
                message: phase.copy
            ))
            #expect(resolution.primaryAction == .relayStatus)
            #expect(resolution.secondaryAction == .explore)
        }
    }

    @Test("Failure and missing loaded contacts keep their retry behavior")
    func retryStatesRemainRefreshActions() {
        let failed = resolve(
            phase: .failed("offline"),
            hasFollows: true
        )
        let missingContacts = resolve(
            phase: .loaded,
            hasFollows: false
        )

        #expect(failed.emptyState == .liveError(message: "offline"))
        #expect(failed.primaryAction == .refresh)
        #expect(missingContacts.emptyState == .noContacts)
        #expect(missingContacts.primaryAction == .refresh)
    }

    @Test("Idle and loaded Home preserve their existing contact policy")
    func idleAndLoadedPreserveContactPolicy() {
        let idleWithoutFollows = resolve(
            phase: .idle,
            hasFollows: false
        )
        let loadedWithFollows = resolve(
            phase: .loaded,
            hasFollows: true
        )

        #expect(idleWithoutFollows.emptyState == .noContacts)
        #expect(idleWithoutFollows.primaryAction == .relayStatus)
        #expect(loadedWithFollows.emptyState == .home)
        #expect(loadedWithFollows.primaryAction == .relayStatus)
    }

    @Test("Non-live and generic timelines keep their existing destinations")
    func genericTimelinesPreserveDestinations() {
        let signedOutHome = resolve(
            hasLiveAccount: false,
            timeline: .home
        )
        let relays = resolve(timeline: .relays)
        let lists = resolve(timeline: .lists)

        #expect(signedOutHome.emptyState == .home)
        #expect(signedOutHome.primaryAction == .relayStatus)
        #expect(signedOutHome.secondaryAction == .explore)
        #expect(relays.emptyState == .relays)
        #expect(relays.primaryAction == .relayStatus)
        #expect(relays.secondaryAction == nil)
        #expect(lists.emptyState == .lists)
        #expect(lists.primaryAction == .settings)
        #expect(lists.secondaryAction == nil)
    }

    @Test("Coordinator routes refresh and navigation effects")
    func coordinatorRoutesEffects() {
        let actions = EmptyStateActionHandlerSpy()
        let coordinator = HomeTimelineEmptyStateActionCoordinator(
            actions: actions
        )
        var effects: [EmptyStateEffect] = []

        coordinator.performPrimaryAction(
            interaction: .liveHome,
            presentRelayStatus: { effects.append(.relayStatus) },
            presentSettings: { effects.append(.settings) }
        )
        actions.phase = .loaded
        actions.hasFollowedPubkeysForEmptyState = true
        coordinator.performPrimaryAction(
            interaction: .liveHome,
            presentRelayStatus: { effects.append(.relayStatus) },
            presentSettings: { effects.append(.settings) }
        )
        coordinator.performPrimaryAction(
            interaction: HomeTimelineInteractionContext(
                hasLiveAccount: true,
                timeline: .lists
            ),
            presentRelayStatus: { effects.append(.relayStatus) },
            presentSettings: { effects.append(.settings) }
        )
        coordinator.performSecondaryAction(
            interaction: .liveHome,
            selectExplore: { effects.append(.explore) }
        )
        coordinator.performSecondaryAction(
            interaction: HomeTimelineInteractionContext(
                hasLiveAccount: true,
                timeline: .relays
            ),
            selectExplore: { effects.append(.explore) }
        )

        #expect(actions.refreshCount == 1)
        #expect(effects == [.relayStatus, .settings, .explore])
    }

    private func resolve(
        hasLiveAccount: Bool = true,
        timeline: TimelineKind = .home,
        phase: NostrHomeTimelinePhase = .loaded,
        hasFollows: Bool = true
    ) -> HomeTimelineEmptyStatePolicy.Resolution {
        HomeTimelineEmptyStatePolicy.resolve(context(
            hasLiveAccount: hasLiveAccount,
            timeline: timeline,
            phase: phase,
            hasFollows: hasFollows
        ))
    }

    private func context(
        hasLiveAccount: Bool = true,
        timeline: TimelineKind = .home,
        phase: NostrHomeTimelinePhase = .loaded,
        hasFollows: Bool = true
    ) -> HomeTimelineEmptyStateContext {
        HomeTimelineEmptyStateContext(
            interaction: HomeTimelineInteractionContext(
                hasLiveAccount: hasLiveAccount,
                timeline: timeline
            ),
            phase: phase,
            hasFollowedPubkeys: hasFollows
        )
    }
}

private enum EmptyStateEffect: Equatable {
    case relayStatus
    case settings
    case explore
}

private extension HomeTimelineInteractionContext {
    static let liveHome = HomeTimelineInteractionContext(
        hasLiveAccount: true,
        timeline: .home
    )
}

@MainActor
private final class EmptyStateActionHandlerSpy:
    HomeTimelineEmptyStateActionHandling {
    var phase: NostrHomeTimelinePhase = .failed("offline")
    var hasFollowedPubkeysForEmptyState = false
    private(set) var refreshCount = 0

    func refresh() {
        refreshCount += 1
    }
}
