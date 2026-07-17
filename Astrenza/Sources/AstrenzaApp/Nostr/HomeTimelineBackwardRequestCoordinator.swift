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

    init(
        contentCoordinator: HomeTimelineContentCoordinator,
        timelineRepository: HomeTimelineRepository,
        projectionController: HomeFeedProjectionController,
        backwardRequestRegistry: HomeTimelineBackwardRequestRegistry,
        syncPlanner: HomeTimelineSyncPlanner,
        packetInstaller: PacketInstaller?
    ) {
        self.contentCoordinator = contentCoordinator
        self.timelineRepository = timelineRepository
        self.projectionController = projectionController
        self.backwardRequestRegistry = backwardRequestRegistry
        self.syncPlanner = syncPlanner
        self.packetInstaller = packetInstaller
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

        return await install(
            packet,
            feed: feed,
            fallbackRelayURL: content.resolvedRelays.first,
            failurePrefix: "gap enqueue failed"
        ) {
            backwardRequestRegistry.registerGap(
                groupID: packet.groupID,
                context: feed.context,
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID,
                direction: direction
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
        register: () -> Void
    ) async -> HomeTimelineBackwardRequestOutcome {
        guard let packetInstaller, !Task.isCancelled else { return .unavailable }
        register()
        do {
            try await packetInstaller([packet], .authors)
        } catch is CancellationError {
            backwardRequestRegistry.remove(groupID: packet.groupID)
            return .unavailable
        } catch {
            backwardRequestRegistry.remove(groupID: packet.groupID)
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
            backwardRequestRegistry.remove(groupID: packet.groupID)
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

    private func timelineEvent(
        id: String,
        inMemoryEvents: [NostrEvent]
    ) -> NostrEvent? {
        inMemoryEvents.first { $0.id == id } ?? timelineRepository.event(id: id)
    }
}
