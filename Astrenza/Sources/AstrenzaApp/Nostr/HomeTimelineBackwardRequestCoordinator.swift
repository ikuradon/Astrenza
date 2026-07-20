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

    private enum StageOutcome {
        case unavailable
        case completed(
            definition: NostrFeedDefinitionRecord,
            completion: NostrBackwardREQCompletion
        )
        case failed(HomeTimelineBackwardRequestDiagnostic)

        var publicOutcome: HomeTimelineBackwardRequestOutcome {
            switch self {
            case .unavailable:
                .unavailable
            case .completed(let definition, _):
                .completed(definition)
            case .failed(let diagnostic):
                .failed(diagnostic)
            }
        }
    }

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
        let authors = content.followedPubkeys.isEmpty
            ? [account.pubkey]
            : content.followedPubkeys
        guard let plan = syncPlanner.olderNotesPlan(
            account: account,
            followedPubkeys: content.followedPubkeys,
            oldestCreatedAt: oldestCreatedAt,
            relayURLs: content.resolvedRelays,
            contactItems: NostrContactList.items(
                from: content.contactListEvent
            ),
            authorRelayListEvents: content.authorRelayListEvents,
            observedRelayURLsByAuthor:
                timelineRepository.observedRelayURLsByAuthor(authors),
            policy: policy
        )
        else { return .unavailable }

        let primary = await install(
            plan.primaryPackets,
            feed: feed,
            fallbackRelayURL: content.resolvedRelays.first,
            failurePrefix: "older enqueue failed"
        ) { groupID in
            backwardRequestRegistry.registerOlderPage(
                groupID: groupID,
                context: feed.context,
                anchorEventID: content.noteEvents.last?.id,
                requestedLimit: plan.requestedLimit,
                hasRemainingRelayCandidates: plan.hasHedge
            )
        }
        guard case .completed(_, let primaryCompletion) = primary,
              shouldInstallHedge(
                plan: plan,
                completion: primaryCompletion
              )
        else { return primary.publicOutcome }

        return await install(
            plan.hedgePackets,
            feed: feed,
            fallbackRelayURL: content.resolvedRelays.first,
            failurePrefix: "older hedge enqueue failed"
        ) { groupID in
            backwardRequestRegistry.registerOlderPage(
                groupID: groupID,
                context: feed.context,
                anchorEventID: content.noteEvents.last?.id,
                requestedLimit: plan.requestedLimit,
                hasRemainingRelayCandidates: false,
                receivedTimelineEventCount: primaryCompletion.eventCount
            )
        }.publicOutcome
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
        let authors = content.followedPubkeys.isEmpty
            ? [account.pubkey]
            : content.followedPubkeys
        guard let plan = syncPlanner.gapNotesPlan(
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
            observedRelayURLsByAuthor:
                timelineRepository.observedRelayURLsByAuthor(authors),
            policy: policy
        ) else { return .unavailable }

        let pendingGap = PendingGapBackfill(
            newerPostID: gap.newerPostID,
            olderPostID: gap.olderPostID,
            direction: direction
        )
        let primary = await install(
            plan.primaryPackets,
            feed: feed,
            fallbackRelayURL: content.resolvedRelays.first,
            failurePrefix: "gap enqueue failed",
            rollback: { [gapStatePersistence] in
                gapStatePersistence?.markGapUnresolved(
                    pendingGap,
                    context: feed.context
                )
            }
        ) { groupID in
            backwardRequestRegistry.registerGap(
                groupID: groupID,
                context: feed.context,
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID,
                direction: direction,
                requestedLimit: plan.requestedLimit,
                hasRemainingRelayCandidates: plan.hasHedge
            )
            try gapStatePersistence?.markGapRequested(
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID,
                definition: feed.definition
            )
        }
        guard case .completed(_, let primaryCompletion) = primary,
              shouldInstallHedge(plan: plan, completion: primaryCompletion)
        else { return primary.publicOutcome }

        return await install(
            plan.hedgePackets,
            feed: feed,
            fallbackRelayURL: content.resolvedRelays.first,
            failurePrefix: "gap hedge enqueue failed",
            rollback: { [gapStatePersistence] in
                gapStatePersistence?.markGapUnresolved(
                    pendingGap,
                    context: feed.context
                )
            }
        ) { groupID in
            backwardRequestRegistry.registerGap(
                groupID: groupID,
                context: feed.context,
                newerEventID: gap.newerPostID,
                olderEventID: gap.olderPostID,
                direction: direction,
                requestedLimit: plan.requestedLimit,
                hasRemainingRelayCandidates: false,
                receivedTimelineEventCount: primaryCompletion.eventCount
            )
        }.publicOutcome
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
        _ packets: [NostrREQPacket],
        feed: (definition: NostrFeedDefinitionRecord, context: HomeFeedRuntimeContext),
        fallbackRelayURL: String?,
        failurePrefix: String,
        rollback: (() -> Void)? = nil,
        register: (_ groupID: String) throws -> Void
    ) async -> StageOutcome {
        guard let packet = packets.first,
              packets.allSatisfy({ $0.groupID == packet.groupID }),
              let packetInstaller,
              !Task.isCancelled
        else { return .unavailable }
        do {
            try register(packet.groupID)
        } catch {
            backwardRequestRegistry.remove(groupID: packet.groupID)
            return .failed(HomeTimelineBackwardRequestDiagnostic(
                relayURL: fallbackRelayURL ?? "runtime",
                subscriptionID: packet.subscriptionID,
                message: "\(failurePrefix): \(error.localizedDescription)"
            ))
        }
        do {
            try await packetInstaller(packets, .authors)
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
        guard let completion = await backwardRequestRegistry.waitForCompletion(
            groupID: packet.groupID
        ),
              !Task.isCancelled,
              projectionController.isCurrent(
                feed.context,
                accountID: feed.definition.accountID
              )
        else { return .unavailable }
        return .completed(
            definition: feed.definition,
            completion: completion
        )
    }

    private func shouldInstallHedge(
        plan: HomeTimelineBackwardPacketPlan,
        completion: NostrBackwardREQCompletion
    ) -> Bool {
        plan.hasHedge && (
            completion.status != .completed ||
                completion.eventCount < plan.requestedLimit
        )
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
