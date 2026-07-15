import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline data interaction workflow")
@MainActor
struct HomeTimelineDataInteractionWorkflowTests {
    @Test("Content and dependency state cross one Store-facing boundary")
    func projectsStoreFacingState() {
        let resolution = nip05Resolution()
        let content = ContentDataSpy(
            snapshot: contentSnapshot(relays: ["wss://relay.example"])
        )
        let dependencies = DependencyDataSpy(
            nip05Resolutions: ["author": resolution],
            profileResolutionStates: ["author": .fetching],
            hasPendingWork: true,
            pendingSourceRequestCount: 2
        )
        let workflow = HomeTimelineDataInteractionWorkflow(
            content: content,
            dependencies: dependencies
        )

        #expect(workflow.contentState == content.snapshotResult)
        #expect(workflow.dependencyResolutionState ==
            HomeTimelineDependencyResolutionState(
                nip05Resolutions: ["author": resolution],
                profileResolutionStates: ["author": .fetching]
            ))
        #expect(workflow.dependencyWorkState ==
            HomeTimelineDependencyWorkState(
                hasPendingWork: true,
                pendingSourceRequestCount: 2
            ))
        #expect(content.events == [.snapshot])
        #expect(dependencies.events == [
            .nip05Resolutions,
            .profileResolutionStates,
            .hasPendingWork,
            .pendingSourceRequestCount
        ])
    }

    @Test("Content mutations preserve their atomic snapshot results")
    func routesContentIntents() {
        let installed = contentSnapshot(
            relays: ["wss://provisional.example"]
        )
        let followed = contentSnapshot(followedPubkeys: ["author"])
        let content = ContentDataSpy(
            installedSnapshot: installed,
            followedSnapshot: followed
        )
        let workflow = HomeTimelineDataInteractionWorkflow(
            content: content,
            dependencies: DependencyDataSpy()
        )

        let first = workflow.perform(
            .installProvisionalRelays(["wss://provisional.example"])
        )
        let second = workflow.perform(.replaceFollowedPubkeys(["author"]))

        #expect(first == installed)
        #expect(second == followed)
        #expect(content.events == [
            .installProvisionalRelays(["wss://provisional.example"]),
            .replaceFollowedPubkeys(["author"])
        ])
    }

    @Test("Loader and bootstrap state use the current dependency resolution")
    func composesTimelineStates() {
        let resolution = nip05Resolution()
        let loaderResult = timelineState(relays: ["wss://loader.example"])
        let bootstrapResult = timelineState(
            relays: ["wss://bootstrap-result.example"]
        )
        let bootstrapInput = timelineState(
            relays: ["wss://bootstrap-input.example"]
        )
        let content = ContentDataSpy(
            loaderResult: loaderResult,
            bootstrapResult: bootstrapResult
        )
        let dependencies = DependencyDataSpy(
            nip05Resolutions: ["author": resolution]
        )
        let workflow = HomeTimelineDataInteractionWorkflow(
            content: content,
            dependencies: dependencies
        )

        let loader = workflow.loaderState(relaySyncEvents: [])
        let bootstrap = workflow.runtimeBootstrapState(from: bootstrapInput)

        #expect(loader == loaderResult)
        #expect(bootstrap == bootstrapResult)
        #expect(content.events == [
            .loaderState(["author": resolution], []),
            .runtimeBootstrapState(
                bootstrapInput,
                ["author": resolution]
            )
        ])
        #expect(dependencies.events == [
            .nip05Resolutions,
            .nip05Resolutions
        ])
    }

    #if DEBUG
    @Test("Debug source dependency controls preserve inputs and failures")
    func routesSourceDependencyControls() {
        let dependencies = DependencyDataSpy(
            enqueueResult: true,
            flushResult: true,
            flushFailure: "install failed"
        )
        let workflow = HomeTimelineDataInteractionWorkflow(
            content: ContentDataSpy(),
            dependencies: dependencies
        )
        let sourceDependencies = NostrEventDependencies(
            sourceEventIDs: ["source"]
        )
        let failures = DependencyFailureProbe()

        let didEnqueue = workflow.enqueueSourceDependencies(
            sourceDependencies,
            availableRelayURLs: ["wss://relay.example"],
            now: 42
        )
        let didFlush = workflow.flushSourcePacketInstall { message in
            failures.messages.append(message)
        }

        #expect(didEnqueue)
        #expect(didFlush)
        #expect(failures.messages == ["install failed"])
        #expect(dependencies.events == [
            .enqueueSourceDependencies(
                sourceDependencies,
                NostrDependencyFetchCacheSnapshot(),
                ["wss://relay.example"],
                42
            ),
            .flushSourcePacketInstall
        ])
    }
    #endif

    private func contentSnapshot(
        relays: [String] = [],
        followedPubkeys: [String] = []
    ) -> HomeTimelineContentSnapshot {
        HomeTimelineContentSnapshot(
            resolvedRelays: relays,
            followedPubkeys: followedPubkeys,
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: true
        )
    }

    private func timelineState(
        relays: [String]
    ) -> NostrHomeTimelineState {
        NostrHomeTimelineState(
            relays: relays,
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: []
        )
    }

    private func nip05Resolution() -> NostrNIP05Resolution {
        NostrNIP05Resolution(
            identifier: "alice@example.com",
            pubkey: "author",
            relays: ["wss://relay.example"],
            status: .verified,
            resolvedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

private enum ContentDataEvent: Equatable {
    case snapshot
    case installProvisionalRelays([String])
    case replaceFollowedPubkeys([String])
    case loaderState(
        [String: NostrNIP05Resolution],
        [NostrRelaySyncEventRecord]
    )
    case runtimeBootstrapState(
        NostrHomeTimelineState,
        [String: NostrNIP05Resolution]
    )
}

@MainActor
private final class ContentDataSpy: HomeTimelineContentDataManaging {
    let snapshotResult: HomeTimelineContentSnapshot
    private let installedSnapshot: HomeTimelineContentSnapshot
    private let followedSnapshot: HomeTimelineContentSnapshot
    private let loaderResult: NostrHomeTimelineState
    private let bootstrapResult: NostrHomeTimelineState
    private(set) var events: [ContentDataEvent] = []

    init(
        snapshot: HomeTimelineContentSnapshot = .initial,
        installedSnapshot: HomeTimelineContentSnapshot = .initial,
        followedSnapshot: HomeTimelineContentSnapshot = .initial,
        loaderResult: NostrHomeTimelineState = NostrHomeTimelineState(
            relays: [],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: []
        ),
        bootstrapResult: NostrHomeTimelineState = NostrHomeTimelineState(
            relays: [],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: []
        )
    ) {
        snapshotResult = snapshot
        self.installedSnapshot = installedSnapshot
        self.followedSnapshot = followedSnapshot
        self.loaderResult = loaderResult
        self.bootstrapResult = bootstrapResult
    }

    var snapshot: HomeTimelineContentSnapshot {
        events.append(.snapshot)
        return snapshotResult
    }

    func installProvisionalRelays(
        _ relays: [String]
    ) -> HomeTimelineContentSnapshot {
        events.append(.installProvisionalRelays(relays))
        return installedSnapshot
    }

    func replaceFollowedPubkeys(
        _ pubkeys: [String]
    ) -> HomeTimelineContentSnapshot {
        events.append(.replaceFollowedPubkeys(pubkeys))
        return followedSnapshot
    }

    func loaderState(
        nip05Resolutions: [String: NostrNIP05Resolution],
        relaySyncEvents: [NostrRelaySyncEventRecord]
    ) -> NostrHomeTimelineState {
        events.append(.loaderState(nip05Resolutions, relaySyncEvents))
        return loaderResult
    }

    func runtimeBootstrapState(
        from bootstrapState: NostrHomeTimelineState,
        nip05Resolutions: [String: NostrNIP05Resolution]
    ) -> NostrHomeTimelineState {
        events.append(.runtimeBootstrapState(
            bootstrapState,
            nip05Resolutions
        ))
        return bootstrapResult
    }
}

private enum DependencyDataEvent: Equatable {
    case nip05Resolutions
    case profileResolutionStates
    case hasPendingWork
    case pendingSourceRequestCount
    case enqueueSourceDependencies(
        NostrEventDependencies,
        NostrDependencyFetchCacheSnapshot,
        [String],
        Int
    )
    case flushSourcePacketInstall
}

@MainActor
private final class DependencyDataSpy: HomeTimelineDependencyDataManaging {
    private let nip05ResolutionResult: [String: NostrNIP05Resolution]
    private let profileResolutionStateResult: [String: NostrProfileResolutionState]
    private let hasPendingWorkResult: Bool
    private let pendingSourceRequestCountResult: Int
    private let enqueueResult: Bool
    private let flushResult: Bool
    private let flushFailure: String?
    private(set) var events: [DependencyDataEvent] = []

    init(
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        profileResolutionStates: [String: NostrProfileResolutionState] = [:],
        hasPendingWork: Bool = false,
        pendingSourceRequestCount: Int = 0,
        enqueueResult: Bool = false,
        flushResult: Bool = false,
        flushFailure: String? = nil
    ) {
        nip05ResolutionResult = nip05Resolutions
        profileResolutionStateResult = profileResolutionStates
        hasPendingWorkResult = hasPendingWork
        pendingSourceRequestCountResult = pendingSourceRequestCount
        self.enqueueResult = enqueueResult
        self.flushResult = flushResult
        self.flushFailure = flushFailure
    }

    var nip05Resolutions: [String: NostrNIP05Resolution] {
        events.append(.nip05Resolutions)
        return nip05ResolutionResult
    }

    var profileResolutionStates: [String: NostrProfileResolutionState] {
        events.append(.profileResolutionStates)
        return profileResolutionStateResult
    }

    var hasPendingWork: Bool {
        events.append(.hasPendingWork)
        return hasPendingWorkResult
    }

    var pendingSourceRequestCount: Int {
        events.append(.pendingSourceRequestCount)
        return pendingSourceRequestCountResult
    }

    #if DEBUG
    func enqueueSourceDependencies(
        _ dependencies: NostrEventDependencies,
        cacheSnapshot: NostrDependencyFetchCacheSnapshot,
        availableRelayURLs: [String],
        now: Int
    ) -> Bool {
        events.append(.enqueueSourceDependencies(
            dependencies,
            cacheSnapshot,
            availableRelayURLs,
            now
        ))
        return enqueueResult
    }

    func flushSourcePacketInstall(
        onFailure: @escaping HomeDependencyInstallFailureHandler
    ) -> Bool {
        events.append(.flushSourcePacketInstall)
        if let flushFailure {
            onFailure(flushFailure)
        }
        return flushResult
    }
    #endif
}

@MainActor
private final class DependencyFailureProbe {
    var messages: [String] = []
}
