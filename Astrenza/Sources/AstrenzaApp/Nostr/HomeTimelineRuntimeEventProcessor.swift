import AstrenzaCore

protocol HomeTimelineProjectedEventIngesting: Sendable {
    func ingestForward(
        _ request: HomeTimelineForwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult

    func ingestBackward(
        _ request: HomeTimelineBackwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult
}

extension HomeTimelineEventIngestor: HomeTimelineProjectedEventIngesting {}

struct HomeTimelineRuntimeEventPresentationState: Equatable, Sendable {
    let receivedWhileRealtime: Bool
    let hasRestoreProjectionAnchor: Bool
    let isTimelineAtNewestWindow: Bool
    let hasPendingEvents: Bool
}

struct HomeTimelineRuntimeEventProcessingResult: Equatable, Sendable {
    let applicationPlan: HomeTimelineRuntimeEventApplicationPlan
    let backwardRequestKey: String?
}

enum HomeTimelineRuntimeEventProcessingOutcome: Equatable, Sendable {
    case ignored
    case processed(HomeTimelineRuntimeEventProcessingResult)
    case persistenceFailed(String)
}

@MainActor
final class HomeTimelineRuntimeEventProcessor {
    private let eventIngestor: any HomeTimelineProjectedEventIngesting
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    private let applicationPlanner: HomeTimelineRuntimeEventApplicationPlanner

    init(
        eventIngestor: any HomeTimelineProjectedEventIngesting,
        backwardRequestRegistry: HomeTimelineBackwardRequestRegistry,
        feedSyncCoordinator: HomeTimelineFeedSyncCoordinator,
        applicationPlanner: HomeTimelineRuntimeEventApplicationPlanner = .init()
    ) {
        self.eventIngestor = eventIngestor
        self.backwardRequestRegistry = backwardRequestRegistry
        self.feedSyncCoordinator = feedSyncCoordinator
        self.applicationPlanner = applicationPlanner
    }

    func process(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent,
        forwardPresentationState: () -> HomeTimelineRuntimeEventPresentationState,
        ensureFeedDefinition: () async -> Void,
        activeFeedContext: () -> HomeFeedRuntimeContext?
    ) async -> HomeTimelineRuntimeEventProcessingOutcome {
        if HomeTimelineSyncPlanner.isHomeForwardSubscription(subscriptionID) {
            return await processForward(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event,
                presentationState: forwardPresentationState,
                ensureFeedDefinition: ensureFeedDefinition,
                activeFeedContext: activeFeedContext
            )
        }

        return await processBackward(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            event: event,
            ensureFeedDefinition: ensureFeedDefinition,
            activeFeedContext: activeFeedContext
        )
    }

    private func processForward(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent,
        presentationState: () -> HomeTimelineRuntimeEventPresentationState,
        ensureFeedDefinition: () async -> Void,
        activeFeedContext: () -> HomeFeedRuntimeContext?
    ) async -> HomeTimelineRuntimeEventProcessingOutcome {
        guard event.kind == 1 || event.kind == 5 || event.kind == 6 else {
            return .ignored
        }

        await ensureFeedDefinition()
        let requestID = feedSyncCoordinator.requestID(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )
        let requestContext = feedSyncCoordinator.context(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )

        let ingestResult: HomeTimelineProjectedEventIngestResult
        do {
            ingestResult = try await eventIngestor.ingestForward(
                HomeTimelineForwardEventIngestRequest(
                    event: event,
                    relayURL: relayURL,
                    activeFeedContext: activeFeedContext(),
                    requestContext: requestContext,
                    sourceRequestID: requestID
                )
            )
        } catch {
            return .persistenceFailed("event save failed: \(error.localizedDescription)")
        }

        let presentationState = presentationState()
        let applicationPlan = applicationPlanner.planForward(.init(
            event: event,
            embeddedEvent: ingestResult.eventResult.embeddedEvent,
            projectsIntoCurrentFeed: ingestResult.projectsIntoCurrentFeed,
            receivedWhileRealtime: presentationState.receivedWhileRealtime,
            hasRestoreProjectionAnchor: presentationState.hasRestoreProjectionAnchor,
            isTimelineAtNewestWindow: presentationState.isTimelineAtNewestWindow,
            hasPendingEvents: presentationState.hasPendingEvents
        ))
        return .processed(HomeTimelineRuntimeEventProcessingResult(
            applicationPlan: applicationPlan,
            backwardRequestKey: nil
        ))
    }

    private func processBackward(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent,
        ensureFeedDefinition: () async -> Void,
        activeFeedContext: () -> HomeFeedRuntimeContext?
    ) async -> HomeTimelineRuntimeEventProcessingOutcome {
        let requestKey = backwardRequestRegistry.key(for: subscriptionID)
        let request = requestKey.flatMap { backwardRequestRegistry.request(for: $0) }
        let projectionReason: HomeTimelineFeedProjectionReason? = if request?.isOlderPage == true {
            .older
        } else if request?.gap != nil {
            .gap
        } else {
            nil
        }
        let isTimelineBackfill = projectionReason != nil
        if isTimelineBackfill {
            await ensureFeedDefinition()
        }

        let sourceRequestID = feedSyncCoordinator.requestID(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )
        let activeRequestContext = feedSyncCoordinator.context(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )

        let ingestResult: HomeTimelineProjectedEventIngestResult
        do {
            // 配信可否はbackward request registryで判定する。provenance用requestStartedは
            // 最初のEVENT到着時点でまだqueue内に残っている場合がある。
            ingestResult = try await eventIngestor.ingestBackward(
                HomeTimelineBackwardEventIngestRequest(
                    event: event,
                    relayURL: relayURL,
                    activeFeedContext: activeFeedContext(),
                    requestContext: request?.feedContext,
                    activeRequestContext: activeRequestContext,
                    projectionReason: projectionReason,
                    sourceRequestID: sourceRequestID
                )
            )
        } catch {
            return .persistenceFailed("backward event save failed: \(error.localizedDescription)")
        }

        let applicationPlan = applicationPlanner.planBackward(.init(
            event: event,
            embeddedEvent: ingestResult.eventResult.embeddedEvent,
            projectsIntoCurrentFeed: ingestResult.projectsIntoCurrentFeed,
            isTimelineBackfill: isTimelineBackfill
        ))
        return .processed(HomeTimelineRuntimeEventProcessingResult(
            applicationPlan: applicationPlan,
            backwardRequestKey: requestKey
        ))
    }
}
