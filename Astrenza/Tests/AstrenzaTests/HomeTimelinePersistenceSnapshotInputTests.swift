import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline persistence snapshot input")
@MainActor
struct HomePersistenceSnapshotInputTests {
    @Test("Persistence input captures every field from one content snapshot")
    func capturesAtomicContentSnapshot() {
        let resolution = NostrNIP05Resolution(
            identifier: "alice@example.com",
            pubkey: "author",
            relays: ["wss://relay.example"],
            status: .verified,
            resolvedAt: Date(timeIntervalSince1970: 100)
        )
        let note = event(id: "1", kind: 1)
        let metadata = event(id: "2", kind: 0)
        let relayList = event(id: "3", kind: 10_002)
        let contactList = event(id: "4", kind: 3)
        let snapshot = HomeTimelineContentSnapshot(
            resolvedRelays: ["wss://relay.example"],
            followedPubkeys: ["author"],
            noteEvents: [note],
            metadataEvents: [metadata],
            relayListEvent: relayList,
            contactListEvent: contactList,
            hasMoreOlder: false
        )
        let content = PersistenceContentDataStub(snapshot: snapshot)
        let dependencies = PersistenceDependencyDataStub(
            nip05Resolutions: ["author": resolution]
        )
        let workflow = HomeTimelineDataInteractionWorkflow(
            content: content,
            dependencies: dependencies
        )

        let input = workflow.persistenceSnapshotInput(accountID: "account")

        #expect(input.accountID == "account")
        #expect(input.relays == snapshot.resolvedRelays)
        #expect(input.followedPubkeys == snapshot.followedPubkeys)
        #expect(input.noteEvents == snapshot.noteEvents)
        #expect(input.metadataEvents == snapshot.metadataEvents)
        #expect(input.relayListEvent == snapshot.relayListEvent)
        #expect(input.contactListEvent == snapshot.contactListEvent)
        #expect(input.nip05Resolutions == ["author": resolution])
        #expect(input.hasMoreOlder == snapshot.hasMoreOlder)
        #expect(content.snapshotReadCount == 1)
        #expect(dependencies.nip05ReadCount == 1)
    }

    private func event(id: Character, kind: Int) -> NostrEvent {
        NostrEvent(
            id: String(repeating: id, count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: 100,
            kind: kind,
            tags: [],
            content: "",
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
private final class PersistenceContentDataStub:
    HomeTimelineContentDataManaging {
    private let snapshotResult: HomeTimelineContentSnapshot
    private(set) var snapshotReadCount = 0

    init(snapshot: HomeTimelineContentSnapshot) {
        snapshotResult = snapshot
    }

    var snapshot: HomeTimelineContentSnapshot {
        snapshotReadCount += 1
        return snapshotResult
    }

    func installProvisionalRelays(
        _ relays: [String]
    ) -> HomeTimelineContentSnapshot {
        _ = relays
        return snapshotResult
    }

    func replaceFollowedPubkeys(
        _ pubkeys: [String]
    ) -> HomeTimelineContentSnapshot {
        _ = pubkeys
        return snapshotResult
    }

    func loaderState(
        nip05Resolutions: [String: NostrNIP05Resolution],
        relaySyncEvents: [NostrRelaySyncEventRecord]
    ) -> NostrHomeTimelineState {
        _ = nip05Resolutions
        _ = relaySyncEvents
        return NostrHomeTimelineState(
            relays: [],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: []
        )
    }

    func runtimeBootstrapState(
        from bootstrapState: NostrHomeTimelineState,
        nip05Resolutions: [String: NostrNIP05Resolution]
    ) -> NostrHomeTimelineState {
        _ = nip05Resolutions
        return bootstrapState
    }
}

@MainActor
private final class PersistenceDependencyDataStub:
    HomeTimelineDependencyDataManaging {
    private let resolutionResult: [String: NostrNIP05Resolution]
    private(set) var nip05ReadCount = 0

    init(nip05Resolutions: [String: NostrNIP05Resolution]) {
        resolutionResult = nip05Resolutions
    }

    var nip05Resolutions: [String: NostrNIP05Resolution] {
        nip05ReadCount += 1
        return resolutionResult
    }

    var profileResolutionStates: [String: NostrProfileResolutionState] {
        [:]
    }

    var hasPendingWork: Bool {
        false
    }

    var pendingSourceRequestCount: Int {
        0
    }

    #if DEBUG
    func enqueueSourceDependencies(
        _ dependencies: NostrEventDependencies,
        cacheSnapshot: NostrDependencyFetchCacheSnapshot,
        availableRelayURLs: [String],
        now: Int
    ) -> Bool {
        _ = dependencies
        _ = cacheSnapshot
        _ = availableRelayURLs
        _ = now
        return false
    }

    func flushSourcePacketInstall(
        onFailure: @escaping HomeDependencyInstallFailureHandler
    ) -> Bool {
        _ = onFailure
        return false
    }
    #endif
}
