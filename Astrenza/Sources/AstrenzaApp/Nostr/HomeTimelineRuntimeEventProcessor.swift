import AstrenzaCore

protocol HomeTimelineProjectedEventIngesting: Sendable {
    func ingestForward(
        _ request: HomeTimelineForwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult

    func ingestBackward(
        _ request: HomeTimelineBackwardEventIngestRequest
    ) async throws -> HomeTimelineProjectedEventIngestResult

    func ingestProjectedEvents(
        _ requests: [HomeTimelineProjectedEventIngestRequest]
    ) async throws -> [HomeTimelineProjectedEventIngestResult]
}

extension HomeTimelineProjectedEventIngesting {
    func ingestProjectedEvents(
        _ requests: [HomeTimelineProjectedEventIngestRequest]
    ) async throws -> [HomeTimelineProjectedEventIngestResult] {
        var results: [HomeTimelineProjectedEventIngestResult] = []
        results.reserveCapacity(requests.count)
        for request in requests {
            switch request {
            case .forward(let forward):
                results.append(try await ingestForward(forward))
            case .backward(let backward):
                results.append(try await ingestBackward(backward))
            }
        }
        return results
    }
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
    struct PersistenceRetryPolicy: Equatable, Sendable {
        let maxAttempts: Int
        let initialDelayNanoseconds: UInt64
        let maximumDelayNanoseconds: UInt64

        static let `default` = PersistenceRetryPolicy(
            maxAttempts: 3,
            initialDelayNanoseconds: 25_000_000,
            maximumDelayNanoseconds: 100_000_000
        )

        func delayNanoseconds(afterFailedAttempt attempt: Int) -> UInt64 {
            guard attempt > 0, initialDelayNanoseconds > 0 else { return 0 }
            let shift = min(attempt - 1, 10)
            let (multiplied, overflow) = initialDelayNanoseconds
                .multipliedReportingOverflow(by: UInt64(1 << shift))
            return min(
                overflow ? UInt64.max : multiplied,
                maximumDelayNanoseconds
            )
        }
    }

    typealias Sleep = @Sendable (_ nanoseconds: UInt64) async throws -> Void

    private let eventIngestor: any HomeTimelineProjectedEventIngesting
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    private let applicationPlanner: HomeTimelineRuntimeEventApplicationPlanner
    private let persistenceRetryPolicy: PersistenceRetryPolicy
    private let sleep: Sleep

    init(
        eventIngestor: any HomeTimelineProjectedEventIngesting,
        backwardRequestRegistry: HomeTimelineBackwardRequestRegistry,
        feedSyncCoordinator: HomeTimelineFeedSyncCoordinator,
        applicationPlanner: HomeTimelineRuntimeEventApplicationPlanner = .init(),
        persistenceRetryPolicy: PersistenceRetryPolicy = .default,
        sleep: @escaping Sleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.eventIngestor = eventIngestor
        self.backwardRequestRegistry = backwardRequestRegistry
        self.feedSyncCoordinator = feedSyncCoordinator
        self.applicationPlanner = applicationPlanner
        self.persistenceRetryPolicy = persistenceRetryPolicy
        self.sleep = sleep
    }

    func process(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent,
        forwardPresentationState: () -> HomeTimelineRuntimeEventPresentationState,
        ensureFeedDefinition: () async -> Void,
        activeFeedContext: () -> HomeFeedRuntimeContext?
    ) async -> HomeTimelineRuntimeEventProcessingOutcome {
        await process(
            [RuntimeEventProcessingRequest(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event
            )],
            forwardPresentationState: forwardPresentationState,
            ensureFeedDefinition: ensureFeedDefinition,
            activeFeedContext: activeFeedContext
        )[0]
    }

    func process(
        _ requests: [RuntimeEventProcessingRequest],
        forwardPresentationState: () -> HomeTimelineRuntimeEventPresentationState,
        ensureFeedDefinition: () async -> Void,
        activeFeedContext: () -> HomeFeedRuntimeContext?
    ) async -> [HomeTimelineRuntimeEventProcessingOutcome] {
        guard !requests.isEmpty else { return [] }
        if requests.contains(where: requiresFeedDefinition) {
            await ensureFeedDefinition()
        }
        let feedContext = activeFeedContext()
        let prepared = requests.map { prepare($0, activeFeedContext: feedContext) }
        let ingestRequests = prepared.compactMap { $0?.ingestRequest }

        let ingestResults: [HomeTimelineProjectedEventIngestResult]
        do {
            ingestResults = try await ingestWithRetry(ingestRequests)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else {
                return prepared.map { _ in .ignored }
            }
            return prepared.map { item in
                guard let item else { return .ignored }
                return .persistenceFailed(
                    "\(item.persistenceFailurePrefix): \(error.localizedDescription)"
                )
            }
        }

        var resultIndex = 0
        return prepared.map { item in
            guard let item else { return .ignored }
            let ingestResult = ingestResults[resultIndex]
            resultIndex += 1
            let applicationPlan: HomeTimelineRuntimeEventApplicationPlan
            switch item.kind {
            case .forward:
                let presentationState = forwardPresentationState()
                applicationPlan = applicationPlanner.planForward(.init(
                    event: item.event,
                    embeddedEvent: ingestResult.eventResult.embeddedEvent,
                    projectsIntoCurrentFeed: ingestResult.projectsIntoCurrentFeed,
                    receivedWhileRealtime: presentationState.receivedWhileRealtime,
                    hasRestoreProjectionAnchor: presentationState.hasRestoreProjectionAnchor,
                    isTimelineAtNewestWindow: presentationState.isTimelineAtNewestWindow,
                    hasPendingEvents: presentationState.hasPendingEvents
                ))
            case .backward(let isTimelineBackfill):
                applicationPlan = applicationPlanner.planBackward(.init(
                    event: item.event,
                    embeddedEvent: ingestResult.eventResult.embeddedEvent,
                    projectsIntoCurrentFeed: ingestResult.projectsIntoCurrentFeed,
                    isTimelineBackfill: isTimelineBackfill
                ))
            }
            return .processed(HomeTimelineRuntimeEventProcessingResult(
                applicationPlan: applicationPlan,
                backwardRequestKey: item.backwardRequestKey
            ))
        }
    }

    private func ingestWithRetry(
        _ requests: [HomeTimelineProjectedEventIngestRequest]
    ) async throws -> [HomeTimelineProjectedEventIngestResult] {
        let maximumAttempts = max(1, persistenceRetryPolicy.maxAttempts)
        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                return try await eventIngestor.ingestProjectedEvents(requests)
            } catch {
                guard !(error is CancellationError), !Task.isCancelled else {
                    throw CancellationError()
                }
                guard attempt < maximumAttempts else { throw error }
                let delay = persistenceRetryPolicy.delayNanoseconds(
                    afterFailedAttempt: attempt
                )
                if delay > 0 {
                    try await sleep(delay)
                }
                attempt += 1
            }
        }
    }

    private func prepare(
        _ input: RuntimeEventProcessingRequest,
        activeFeedContext: HomeFeedRuntimeContext?
    ) -> PreparedEvent? {
        if HomeTimelineSyncPlanner.isHomeForwardSubscription(input.subscriptionID) {
            guard input.event.kind == 1 || input.event.kind == 5 || input.event.kind == 6 else {
                return nil
            }
            return PreparedEvent(
                event: input.event,
                ingestRequest: .forward(HomeTimelineForwardEventIngestRequest(
                    event: input.event,
                    relayURL: input.relayURL,
                    activeFeedContext: activeFeedContext,
                    requestContext: feedSyncCoordinator.context(
                        relayURL: input.relayURL,
                        subscriptionID: input.subscriptionID
                    ),
                    sourceRequestID: feedSyncCoordinator.requestID(
                        relayURL: input.relayURL,
                        subscriptionID: input.subscriptionID
                    )
                )),
                kind: .forward,
                backwardRequestKey: nil,
                persistenceFailurePrefix: "event save failed"
            )
        }

        let requestKey = backwardRequestRegistry.key(for: input.subscriptionID)
        let request = requestKey.flatMap { backwardRequestRegistry.request(for: $0) }
        let projectionReason: HomeTimelineFeedProjectionReason? = if request?.isOlderPage == true {
            .older
        } else if request?.gap != nil {
            .gap
        } else {
            nil
        }
        let isTimelineBackfill = projectionReason != nil
        // 配信可否はbackward request registryで判定する。provenance用requestStartedは
        // 最初のEVENT到着時点でまだqueue内に残っている場合がある。
        return PreparedEvent(
            event: input.event,
            ingestRequest: .backward(HomeTimelineBackwardEventIngestRequest(
                event: input.event,
                relayURL: input.relayURL,
                activeFeedContext: activeFeedContext,
                requestContext: request?.feedContext,
                activeRequestContext: feedSyncCoordinator.context(
                    relayURL: input.relayURL,
                    subscriptionID: input.subscriptionID
                ),
                projectionReason: projectionReason,
                sourceRequestID: feedSyncCoordinator.requestID(
                    relayURL: input.relayURL,
                    subscriptionID: input.subscriptionID
                )
            )),
            kind: .backward(isTimelineBackfill: isTimelineBackfill),
            backwardRequestKey: requestKey,
            persistenceFailurePrefix: "backward event save failed"
        )
    }

    private func requiresFeedDefinition(
        _ request: RuntimeEventProcessingRequest
    ) -> Bool {
        if HomeTimelineSyncPlanner.isHomeForwardSubscription(request.subscriptionID) {
            return request.event.kind == 1 || request.event.kind == 5 || request.event.kind == 6
        }
        guard let key = backwardRequestRegistry.key(for: request.subscriptionID),
              let backward = backwardRequestRegistry.request(for: key)
        else { return false }
        return backward.isOlderPage || backward.gap != nil
    }

    private struct PreparedEvent {
        enum Kind {
            case forward
            case backward(isTimelineBackfill: Bool)
        }

        let event: NostrEvent
        let ingestRequest: HomeTimelineProjectedEventIngestRequest
        let kind: Kind
        let backwardRequestKey: String?
        let persistenceFailurePrefix: String
    }
}
