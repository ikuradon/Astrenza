import AstrenzaCore
import Foundation

struct HomeTimelineSnapshotInput: Sendable {
    let accountID: String
    let relays: [String]
    let followedPubkeys: [String]
    let noteEvents: [NostrEvent]
    let metadataEvents: [NostrEvent]
    let relayListEvent: NostrEvent?
    let contactListEvent: NostrEvent?
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let hasMoreOlder: Bool
}

struct HomeTimelineMetadataSnapshot: Sendable {
    let accountID: String
    let relays: [String]
    let followedPubkeys: [String]
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let hasMoreOlder: Bool
}

struct HomeTimelineSnapshotSaveReceipt: Sendable {
    let definition: NostrFeedDefinitionRecord
    let sourceAuthors: [String]
    let projectionGeneration: UInt64
    let window: NostrFeedWindow?
    let savedAt: Int
}

@MainActor
final class HomeTimelineSnapshotCoordinator {
    private let persistenceWorker: HomeTimelinePersistenceWorker?
    private let projectionController: HomeFeedProjectionController

    init(
        persistenceWorker: HomeTimelinePersistenceWorker?,
        projectionController: HomeFeedProjectionController
    ) {
        self.persistenceWorker = persistenceWorker
        self.projectionController = projectionController
    }

    func restoredState(accountID: String) async -> NostrHomeTimelineState? {
        guard let persistenceWorker else { return nil }
        return await persistenceWorker.restoredState(accountID: accountID)
    }

    func persistSnapshot(
        _ input: HomeTimelineSnapshotInput,
        savedAt: Int = Int(Date().timeIntervalSince1970)
    ) async -> HomeTimelineSnapshotSaveReceipt? {
        guard let persistenceWorker,
              let plan = await projectionController.definitionPlan(
                accountID: input.accountID,
                followedPubkeys: input.followedPubkeys,
                now: savedAt
        )
        else { return nil }

        let snapshot = persistenceSnapshot(
            input: input,
            plan: plan,
            savedAt: savedAt
        )
        let projectionGeneration = projectionController.generation

        do {
            let window = try await persistenceWorker.saveFeedSnapshot(snapshot)
            return HomeTimelineSnapshotSaveReceipt(
                definition: plan.definition,
                sourceAuthors: plan.sourceAuthors,
                projectionGeneration: projectionGeneration,
                window: window,
                savedAt: savedAt
            )
        } catch {
            return nil
        }
    }

    private func persistenceSnapshot(
        input: HomeTimelineSnapshotInput,
        plan: HomeFeedDefinitionPlan,
        savedAt: Int
    ) -> HomeTimelineFeedPersistenceSnapshot {
        let projectionEvents = HomeTimelinePersistenceProjection.boundedEvents(
            from: input.noteEvents,
            allowedAuthors: Set(plan.authors)
        )
        let metadataPubkeys = Set(projectionEvents.map(\.pubkey)).union([input.accountID])
        let state = NostrHomeTimelineState(
            relays: input.relays,
            followedPubkeys: input.followedPubkeys,
            noteEvents: projectionEvents,
            metadataEvents: input.metadataEvents.filter { metadataPubkeys.contains($0.pubkey) },
            relayListEvent: input.relayListEvent,
            contactListEvent: input.contactListEvent,
            nip05Resolutions: input.nip05Resolutions,
            hasMoreOlder: input.hasMoreOlder,
            relaySyncEvents: []
        )
        let memberships = HomeFeedProjectionBuilder.memberships(
            events: projectionEvents,
            feedID: plan.definition.feedID,
            feedRevision: plan.definition.revision,
            reason: "state",
            insertedAt: savedAt
        )
        let membershipSources = HomeFeedProjectionBuilder.membershipSources(
            events: projectionEvents,
            feedID: plan.definition.feedID,
            feedRevision: plan.definition.revision,
            reason: "state",
            insertedAt: savedAt
        )
        return HomeTimelineFeedPersistenceSnapshot(
            state: state,
            accountID: input.accountID,
            definition: plan.definition,
            memberships: memberships,
            membershipSources: membershipSources,
            savedAt: savedAt,
            windowLimit: projectionController.windowLimit
        )
    }

    @discardableResult
    func activatePersistedSnapshot(
        _ receipt: HomeTimelineSnapshotSaveReceipt,
        accountID: String,
        followedPubkeys: [String]
    ) async -> Bool {
        let currentSourceAuthors = followedPubkeys.isEmpty ? [accountID] : followedPubkeys
        guard receipt.definition.accountID == accountID,
              currentSourceAuthors == receipt.sourceAuthors
        else { return false }
        guard let currentPlan = await projectionController.definitionPlan(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            now: receipt.savedAt
        ) else { return false }
        guard projectionController.generation == receipt.projectionGeneration,
              currentPlan.definition.revision == receipt.definition.revision,
              currentPlan.definition.specificationHash == receipt.definition.specificationHash
        else { return false }

        projectionController.activate(
            definition: receipt.definition,
            window: receipt.window,
            sourceAuthors: receipt.sourceAuthors
        )
        return true
    }

    @discardableResult
    func persistMetadata(
        _ snapshot: HomeTimelineMetadataSnapshot,
        savedAt: Int = Int(Date().timeIntervalSince1970)
    ) async -> Bool {
        guard let persistenceWorker else { return false }
        let state = NostrHomeTimelineState(
            relays: snapshot.relays,
            followedPubkeys: snapshot.followedPubkeys,
            noteEvents: [],
            metadataEvents: [],
            nip05Resolutions: snapshot.nip05Resolutions,
            hasMoreOlder: snapshot.hasMoreOlder,
            relaySyncEvents: []
        )
        do {
            try await persistenceWorker.saveTimelineMetadata(
                state,
                accountID: snapshot.accountID,
                savedAt: savedAt
            )
            return true
        } catch {
            return false
        }
    }
}
