import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline runtime context projector")
@MainActor
struct HomeTimelineRuntimeContextProjectorTests {
    @Test("One snapshot projects interaction event and dependency state")
    func snapshotProjectsRuntimeStates() {
        let snapshot = snapshot()
        let projector = HomeTimelineRuntimeContextProjector()

        #expect(projector.interactionState(from: snapshot) ==
            HomeTimelineRuntimeInteractionState(
                account: snapshot.account,
                resolvedRelays: snapshot.resolvedRelays,
                bootstrapRelayURLs: snapshot.bootstrapRelayURLs,
                policy: snapshot.policy,
                hasRelayRuntime: true,
                isTerminating: true
            ))
        #expect(projector.eventState(from: snapshot) ==
            HomeTimelineRuntimeEventInteractionState(
                account: snapshot.account,
                resolvedRelays: snapshot.resolvedRelays,
                hasRelayRuntime: true,
                receivedWhileRealtime: true
            ))
        #expect(projector.dependencyState(from: snapshot) ==
            HomeTimelineRuntimeDependencyState(
                account: snapshot.account,
                hasRelayRuntime: true
            ))
    }

    @Test("Packet context honors activity override and feed validation")
    func packetContextUsesSnapshotAndOverride() {
        let snapshot = snapshot()
        let projector = HomeTimelineRuntimeContextProjector()
        let packetContext = projector.packetContext(
            from: snapshot,
            isActive: nil,
            isCurrentFeedContext: { _ in true }
        )

        #expect(packetContext.isActive)
        #expect(packetContext.accountID == snapshot.account?.pubkey)
        #expect(packetContext.resolvedRelays == snapshot.resolvedRelays)
        #expect(packetContext.isCurrentFeedContext(feedContext()))
        #expect(!projector.packetContext(
            from: snapshot,
            isActive: false,
            isCurrentFeedContext: { _ in true }
        ).isActive)
    }

    @Test("Presentation and account projections preserve snapshot flags")
    func presentationAndAccountUseSnapshot() {
        let snapshot = snapshot()
        let projector = HomeTimelineRuntimeContextProjector()

        #expect(projector.eventPresentationState(
            from: snapshot,
            receivedWhileRealtime: false
        ) == HomeTimelineRuntimeEventPresentationState(
            receivedWhileRealtime: false,
            hasRestoreProjectionAnchor: true,
            isTimelineAtNewestWindow: false,
            hasPendingEvents: true
        ))
        #expect(projector.isAccountCurrent(
            snapshot.account?.pubkey ?? "missing",
            in: snapshot
        ))
        #expect(!projector.isAccountCurrent("other", in: snapshot))
    }

    private func snapshot() -> HomeTimelineRuntimeStoreSnapshot {
        HomeTimelineRuntimeStoreSnapshot(
            account: NostrAccount(
                pubkey: String(repeating: "a", count: 64),
                displayIdentifier: "context-projector",
                readOnly: true
            ),
            resolvedRelays: ["wss://resolved.example"],
            bootstrapRelayURLs: ["wss://bootstrap.example"],
            policy: .default(
                networkType: .cellular,
                lowPowerMode: true
            ),
            hasRelayRuntime: true,
            isTerminating: true,
            isRuntimeActive: true,
            isRealtime: true,
            hasRestoreProjectionAnchor: true,
            isTimelineAtNewestWindow: false,
            hasPendingEvents: true
        )
    }

    private func feedContext() -> HomeFeedRuntimeContext {
        let accountID = String(repeating: "a", count: 64)
        return HomeFeedRuntimeContext(definition: NostrFeedDefinitionRecord(
            feedID: "home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(#"{"authors":[],"kinds":[1,6]}"#.utf8),
            specificationHash: "context-projector",
            revision: 1,
            createdAt: 1,
            updatedAt: 1
        ))
    }
}
