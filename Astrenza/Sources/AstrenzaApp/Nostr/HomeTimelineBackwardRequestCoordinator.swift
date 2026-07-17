import AstrenzaCore

struct HomeTimelineBackwardRequestDiagnostic: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String
    let message: String
}

enum HomeTimelineBackwardRequestOutcome: Equatable, Sendable {
    case unavailable
    case completed(NostrFeedDefinitionRecord)
    case failed(HomeTimelineBackwardRequestDiagnostic)
}

@MainActor
protocol HomeTimelineGapRequestStatePersisting: Sendable {
    func markGapRequested(
        newerEventID: String,
        olderEventID: String,
        definition: NostrFeedDefinitionRecord
    ) throws

    func markGapUnresolved(
        _ gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    )
}

extension HomeTimelineBackfillPersistence:
    HomeTimelineGapRequestStatePersisting {}

@MainActor
final class HomeTimelineBackwardRequestCoordinator {
    typealias PacketInstaller = @MainActor @Sendable (
        _ packets: [NostrREQPacket],
        _ mergeField: NostrREQMergeField
    ) async throws -> Void

    private let contentCoordinator: HomeTimelineContentCoordinator
    private let timelineRepository: HomeTimelineRepository
    private let projectionController: HomeFeedProjectionController
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let syncPlanner: HomeTimelineSyncPlanner
    private let packetInstaller: PacketInstaller?
    private let gapStatePersistence:
        (any HomeTimelineGapRequestStatePersisting)?

    init(
        contentCoordinator: HomeTimelineContentCoordinator,
        timelineRepository: HomeTimelineRepository,
        projectionController: HomeFeedProjectionController,
        backwardRequestRegistry: HomeTimelineBackwardRequestRegistry,
        syncPlanner: HomeTimelineSyncPlanner,
        packetInstaller: PacketInstaller?,
        gapStatePersistence:
            (any HomeTimelineGapRequestStatePersisting)? = nil
    ) {
        self.contentCoordinator = contentCoordinator
        self.timelineRepository = timelineRepository
        self.projectionController = projectionController
        self.backwardRequestRegistry = backwardRequestRegistry
        self.syncPlanner = syncPlanner
        self.packetInstaller = packetInstaller
        self.gapStatePersistence = gapStatePersistence
    }

    func requestOlder(
        account: NostrAccount,
        policy: NostrSyncPolicy = .default()
    ) async -> HomeTimelineBackwardRequestOutcome {
        guard packetInstaller != nil,
              !backwardRequestRegistry.hasOlderPageRequest
        else { return .unavailable }
        let definitionContent = contentCoordinator.snapshot
        guard let feed = await currentFeed(
            account: account,
            content: definitionContent
        )
        else { return .unavailable }
        let content = contentCoordinator.snapshot
        guard content.followedPubkeys == definitionContent.followedPubkeys,
              let oldestCreatedAt = content.noteEvents.map(\.createdAt).min()
        else { return .unavailable }
        guard let packet = syncPlanner.olderNotesPacket(
            account: account,
            followedPubkeys: content.followedPubkeys,
            oldestCreatedAt: oldestCreatedAt,
            relayURLs: content.resolvedRelays,
            contactItems: NostrContactList.items(
                from: content.contactListEvent
            ),
            authorRelayListEvents: content.authorRelayListEvents,
            policy: policy
        )
        else { return .unavailable }

        return await install(
            packet,
            feed: feed,
            fallbackRelayURL: content.resolvedRelays.first,
            failurePrefix: "older enqueue failed"
        ) {
            backwardRequestRegistry.registerOlderPage(
                groupID: packet.groupID,
                context: feed.context,
                anchorEventID: content.noteEvents.last?.id
            )
        }
    }

    func requestGap(
        account: NostrAccount,
        gap: TimelineGap,
        direction: TimelineGapFillDirection,
        policy: NostrSyncPolicy = .default()
    ) async -> HomeTimelineBackwardRequestOutcome {
        guard packetInstaller != nil,
              !backwardRequestRegistry.containsGap(
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID
              )
        else { return .unavailable }
        let definitionContent = contentCoordinator.snapshot
        guard let feed = await currentFeed(
            account: account,
            content: definitionContent
        )
        else { return .unavailable }
        let content = contentCoordinator.snapshot
        guard content.followedPubkeys == definitionContent.followedPubkeys,
              let newerEvent = timelineEvent(
            id: gap.newerPostID,
            inMemoryEvents: content.noteEvents
        ),
        let olderEvent = timelineEvent(
            id: gap.olderPostID,
            inMemoryEvents: content.noteEvents
        ) else { return .unavailable }
        guard let packet = syncPlanner.gapNotesPacket(
            account: account,
            followedPubkeys: content.followedPubkeys,
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            missingEstimate: gap.missingEstimate,
            relayURLs: content.resolvedRelays,
            contactItems: NostrContactList.items(
                from: content.contactListEvent
            ),
            authorRelayListEvents: content.authorRelayListEvents,
            policy: policy
        ) else { return .unavailable }

        let pendingGap = PendingGapBackfill(
            newerPostID: gap.newerPostID,
            olderPostID: gap.olderPostID,
            direction: direction
        )
        return await install(
            packet,
            feed: feed,
            fallbackRelayURL: content.resolvedRelays.first,
            failurePrefix: "gap enqueue failed",
            rollback: { [gapStatePersistence] in
                gapStatePersistence?.markGapUnresolved(
                    pendingGap,
                    context: feed.context
                )
            }
        ) {
            backwardRequestRegistry.registerGap(
                groupID: packet.groupID,
                context: feed.context,
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID,
                direction: direction
            )
            try gapStatePersistence?.markGapRequested(
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID,
                definition: feed.definition
            )
        }
    }

    private func currentFeed(
        account: NostrAccount,
        content: HomeTimelineContentSnapshot
    ) async -> (definition: NostrFeedDefinitionRecord, context: HomeFeedRuntimeContext)? {
        guard await projectionController.ensureDefinition(
            accountID: account.pubkey,
            followedPubkeys: content.followedPubkeys,
            liveEvents: content.noteEvents
        ) else { return nil }
        guard let definition = projectionController.definition,
              let context = projectionController.runtimeContext(),
              projectionController.isCurrent(context, accountID: account.pubkey)
        else { return nil }
        return (definition, context)
    }

    private func install(
        _ packet: NostrREQPacket,
        feed: (definition: NostrFeedDefinitionRecord, context: HomeFeedRuntimeContext),
        fallbackRelayURL: String?,
        failurePrefix: String,
        rollback: (() -> Void)? = nil,
        register: () throws -> Void
    ) async -> HomeTimelineBackwardRequestOutcome {
        guard let packetInstaller, !Task.isCancelled else { return .unavailable }
        do {
            try register()
        } catch {
            backwardRequestRegistry.remove(groupID: packet.groupID)
            return .failed(HomeTimelineBackwardRequestDiagnostic(
                relayURL: fallbackRelayURL ?? "runtime",
                subscriptionID: packet.subscriptionID,
                message: "\(failurePrefix): \(error.localizedDescription)"
            ))
        }
        do {
            try await packetInstaller([packet], .authors)
        } catch is CancellationError {
            rollbackRequest(
                groupID: packet.groupID,
                rollback: rollback
            )
            return .unavailable
        } catch {
            rollbackRequest(
                groupID: packet.groupID,
                rollback: rollback
            )
            return .failed(HomeTimelineBackwardRequestDiagnostic(
                relayURL: fallbackRelayURL ?? "runtime",
                subscriptionID: packet.subscriptionID,
                message: "\(failurePrefix): \(error.localizedDescription)"
            ))
        }

        guard !Task.isCancelled,
              projectionController.isCurrent(
                feed.context,
                accountID: feed.definition.accountID
              )
        else {
            rollbackRequest(
                groupID: packet.groupID,
                rollback: rollback
            )
            return .unavailable
        }
        guard await backwardRequestRegistry.waitForCompletion(
            groupID: packet.groupID
        ) != nil,
              !Task.isCancelled,
              projectionController.isCurrent(
                feed.context,
                accountID: feed.definition.accountID
              )
        else { return .unavailable }
        return .completed(feed.definition)
    }

    private func rollbackRequest(
        groupID: String,
        rollback: (() -> Void)?
    ) {
        guard backwardRequestRegistry.remove(groupID: groupID) != nil else {
            return
        }
        rollback?()
    }

    private func timelineEvent(
        id: String,
        inMemoryEvents: [NostrEvent]
    ) -> NostrEvent? {
        inMemoryEvents.first { $0.id == id } ?? timelineRepository.event(id: id)
    }
}
