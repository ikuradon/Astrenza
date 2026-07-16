import AstrenzaCore

@MainActor
protocol HomeTimelineContentDataManaging: AnyObject {
    var snapshot: HomeTimelineContentSnapshot { get }

    func installProvisionalRelays(
        _ relays: [String]
    ) -> HomeTimelineContentSnapshot

    func replaceFollowedPubkeys(
        _ pubkeys: [String]
    ) -> HomeTimelineContentSnapshot

    func loaderState(
        nip05Resolutions: [String: NostrNIP05Resolution],
        relaySyncEvents: [NostrRelaySyncEventRecord]
    ) -> NostrHomeTimelineState

    func runtimeBootstrapState(
        from bootstrapState: NostrHomeTimelineState,
        nip05Resolutions: [String: NostrNIP05Resolution]
    ) -> NostrHomeTimelineState
}

extension HomeTimelineContentCoordinator: HomeTimelineContentDataManaging {}

typealias HomeDependencyInstallFailureHandler = @MainActor @Sendable (
    _ message: String
) -> Void

@MainActor
protocol HomeTimelineDependencyDataManaging: AnyObject {
    var nip05Resolutions: [String: NostrNIP05Resolution] { get }
    var profileResolutionStates: [String: NostrProfileResolutionState] { get }
    var hasPendingWork: Bool { get }
    var pendingSourceRequestCount: Int { get }

    #if DEBUG
    func enqueueSourceDependencies(
        _ dependencies: NostrEventDependencies,
        cacheSnapshot: NostrDependencyFetchCacheSnapshot,
        availableRelayURLs: [String],
        now: Int
    ) -> Bool

    func flushSourcePacketInstall(
        onFailure: @escaping HomeDependencyInstallFailureHandler
    ) -> Bool
    #endif
}

extension HomeTimelineDependencyResolutionCoordinator:
    HomeTimelineDependencyDataManaging {}

struct HomeTimelineDependencyResolutionState: Equatable, Sendable {
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let profileResolutionStates: [String: NostrProfileResolutionState]
}

struct HomeTimelineDependencyWorkState: Equatable, Sendable {
    let hasPendingWork: Bool
    let pendingSourceRequestCount: Int
}

enum HomeTimelineDataIntent: Equatable, Sendable {
    case installProvisionalRelays([String])
    case replaceFollowedPubkeys([String])
}

@MainActor
final class HomeTimelineDataInteractionWorkflow {
    private let content: any HomeTimelineContentDataManaging
    private let dependencies: any HomeTimelineDependencyDataManaging

    init(
        content: any HomeTimelineContentDataManaging,
        dependencies: any HomeTimelineDependencyDataManaging
    ) {
        self.content = content
        self.dependencies = dependencies
    }

    var contentState: HomeTimelineContentSnapshot {
        content.snapshot
    }

    var dependencyResolutionState: HomeTimelineDependencyResolutionState {
        HomeTimelineDependencyResolutionState(
            nip05Resolutions: dependencies.nip05Resolutions,
            profileResolutionStates: dependencies.profileResolutionStates
        )
    }

    var dependencyWorkState: HomeTimelineDependencyWorkState {
        HomeTimelineDependencyWorkState(
            hasPendingWork: dependencies.hasPendingWork,
            pendingSourceRequestCount: dependencies.pendingSourceRequestCount
        )
    }

    func perform(
        _ intent: HomeTimelineDataIntent
    ) -> HomeTimelineContentSnapshot {
        switch intent {
        case .installProvisionalRelays(let relays):
            content.installProvisionalRelays(relays)
        case .replaceFollowedPubkeys(let pubkeys):
            content.replaceFollowedPubkeys(pubkeys)
        }
    }

    func runtimeBootstrapState(
        from state: NostrHomeTimelineState
    ) -> NostrHomeTimelineState {
        content.runtimeBootstrapState(
            from: state,
            nip05Resolutions: dependencies.nip05Resolutions
        )
    }

    func loaderState(
        relaySyncEvents: [NostrRelaySyncEventRecord]
    ) -> NostrHomeTimelineState {
        content.loaderState(
            nip05Resolutions: dependencies.nip05Resolutions,
            relaySyncEvents: relaySyncEvents
        )
    }

    func persistenceSnapshotInput(
        accountID: String
    ) -> HomeTimelineSnapshotInput {
        let snapshot = content.snapshot
        return HomeTimelineSnapshotInput(
            accountID: accountID,
            relays: snapshot.resolvedRelays,
            followedPubkeys: snapshot.followedPubkeys,
            noteEvents: snapshot.noteEvents,
            metadataEvents: snapshot.metadataEvents,
            relayListEvent: snapshot.relayListEvent,
            contactListEvent: snapshot.contactListEvent,
            nip05Resolutions: dependencies.nip05Resolutions,
            hasMoreOlder: snapshot.hasMoreOlder
        )
    }
}

#if DEBUG
extension HomeTimelineDataInteractionWorkflow {
    @discardableResult
    func enqueueSourceDependencies(
        _ dependencies: NostrEventDependencies,
        availableRelayURLs: [String],
        now: Int
    ) -> Bool {
        self.dependencies.enqueueSourceDependencies(
            dependencies,
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: availableRelayURLs,
            now: now
        )
    }

    @discardableResult
    func flushSourcePacketInstall(
        onFailure: @escaping HomeDependencyInstallFailureHandler
    ) -> Bool {
        dependencies.flushSourcePacketInstall(onFailure: onFailure)
    }
}
#endif
