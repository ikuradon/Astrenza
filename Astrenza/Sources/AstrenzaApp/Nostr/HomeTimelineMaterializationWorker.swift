import AstrenzaCore

struct HomeTimelineMaterializationInput: Sendable {
    let accountID: String?
    let noteEvents: [NostrEvent]
    let feedWindow: NostrFeedWindow?
    let metadataEvents: [NostrEvent]
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let profileResolutionStates: [String: NostrProfileResolutionState]
    let followedPubkeys: [String]
    let resolvedRelayCount: Int
    let filtersSuspended: Bool
    let filterTimestamp: Int
    let policy: NostrSyncPolicy
}

protocol HomeTimelineMaterializationWorking: Sendable {
    func materialize(
        _ input: HomeTimelineMaterializationInput
    ) async -> sending HomeTimelineMaterializedSnapshot?
}

nonisolated struct HomeTimelineMaterializationWorker:
    HomeTimelineMaterializationWorking {
    private let repository: HomeTimelineRepository
    private let filterProjector: HomeTimelineFilterProjector

    init(
        repository: HomeTimelineRepository,
        filterProjector: HomeTimelineFilterProjector
    ) {
        self.repository = repository
        self.filterProjector = filterProjector
    }

    @concurrent
    func materialize(
        _ input: HomeTimelineMaterializationInput
    ) async -> sending HomeTimelineMaterializedSnapshot? {
        guard !Task.isCancelled else { return nil }
        let filterProjection = filterProjector.projection(
            accountID: input.accountID,
            events: input.noteEvents,
            isSuspended: input.filtersSuspended,
            now: input.filterTimestamp
        )
        guard !Task.isCancelled else { return nil }
        let contextEvents = repository.contextEvents(for: input.noteEvents)
        guard !Task.isCancelled else { return nil }

        return repository.materialize(
            HomeTimelineRenderInput(
                noteEvents: input.noteEvents,
                feedWindow: input.feedWindow,
                contextEvents: contextEvents,
                metadataEvents: input.metadataEvents,
                nip05Resolutions: input.nip05Resolutions,
                profileResolutionStates: input.profileResolutionStates,
                followedPubkeys: input.followedPubkeys,
                resolvedRelayCount: input.resolvedRelayCount,
                filterRules: filterProjection.effectiveRuleSet,
                filterStatus: filterProjection.status,
                timeline: .home,
                policy: input.policy
            )
        )
    }
}
