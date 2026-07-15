import AstrenzaCore
import Foundation

struct HomeTimelineReadContextInput {
    let accountID: String?
    let fallbackEntries: [TimelineFeedEntry]
    let resolvedRelayCount: Int
    let syncPolicy: NostrSyncPolicy
}

@MainActor
protocol HomeTimelineReadContextDataProviding: AnyObject {
    var contentState: HomeTimelineContentSnapshot { get }
    var dependencyResolutionState: HomeTimelineDependencyResolutionState { get }
}

extension HomeTimelineDataInteractionWorkflow:
    HomeTimelineReadContextDataProviding {}

@MainActor
protocol HomeTimelineReadContextProviding: AnyObject {
    func context(
        for input: HomeTimelineReadContextInput,
        applyingHomeFilters: Bool
    ) -> HomeTimelineReadContext
}

@MainActor
final class HomeTimelineReadContextCoordinator:
    HomeTimelineReadContextProviding {
    typealias FollowedPubkeyProjector = @MainActor @Sendable (
        _ pubkeys: [String]
    ) -> Set<String>

    private let data: any HomeTimelineReadContextDataProviding
    private let filter: any HomeTimelineFilterManaging
    private let currentTimestamp: @MainActor @Sendable () -> Int
    private let projectFollowedPubkeys: FollowedPubkeyProjector

    private var followedPubkeySource: [String]?
    private var followedPubkeyProjection: Set<String> = []

    init(
        data: any HomeTimelineReadContextDataProviding,
        filter: any HomeTimelineFilterManaging,
        currentTimestamp: @escaping @MainActor @Sendable () -> Int = {
            Int(Date().timeIntervalSince1970)
        },
        projectFollowedPubkeys: @escaping FollowedPubkeyProjector = {
            Set($0)
        }
    ) {
        self.data = data
        self.filter = filter
        self.currentTimestamp = currentTimestamp
        self.projectFollowedPubkeys = projectFollowedPubkeys
    }

    func context(
        for input: HomeTimelineReadContextInput,
        applyingHomeFilters: Bool = true
    ) -> HomeTimelineReadContext {
        let content = data.contentState
        let dependencies = data.dependencyResolutionState
        return HomeTimelineReadContext(
            accountID: input.accountID,
            fallbackEntries: input.fallbackEntries,
            metadataEvents: content.metadataEvents,
            nip05Resolutions: dependencies.nip05Resolutions,
            profileResolutionStates: dependencies.profileResolutionStates,
            followedPubkeys: followedPubkeys(for: content.followedPubkeys),
            resolvedRelayCount: input.resolvedRelayCount,
            filterRules: applyingHomeFilters
                ? filter.effectiveRuleSet(
                    accountID: input.accountID,
                    now: currentTimestamp()
                )
                : nil,
            syncPolicy: input.syncPolicy
        )
    }

    private func followedPubkeys(for source: [String]) -> Set<String> {
        if followedPubkeySource != source {
            followedPubkeySource = source
            followedPubkeyProjection = projectFollowedPubkeys(source)
        }
        return followedPubkeyProjection
    }
}
