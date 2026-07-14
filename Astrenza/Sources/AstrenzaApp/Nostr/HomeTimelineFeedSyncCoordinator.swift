import AstrenzaCore
import Foundation

struct HomeTimelineFeedSyncRegistration {
    let context: HomeFeedRuntimeContext
    let direction: NostrFeedSyncDirection
    let purpose: NostrFeedSyncPurpose
    let pendingRequestKey: String?
    let gap: PendingGapBackfill?
}

struct HomeTimelineFeedSyncRequestStartResult: Equatable, Sendable {
    let wasHandled: Bool
    let isRealtime: Bool
    let failureMessage: String?
}

enum HomeTimelineFeedSyncStreamCompletion: Equatable, Sendable {
    case eose
    case closed(message: String)
    case timeout(message: String)
}

struct HomeTimelineFeedSyncDiagnostic: Equatable, Sendable {
    let relayURL: String
    let kind: NostrRelaySyncEventKind
    let subscriptionID: String
    let eventCount: Int
    let newestCreatedAt: Int?
    let oldestCreatedAt: Int?
    let message: String
}

struct HomeTimelineFeedSyncTransition: Equatable, Sendable {
    let isRealtime: Bool
    let diagnostic: HomeTimelineFeedSyncDiagnostic
}

@MainActor
final class HomeTimelineFeedSyncCoordinator {
    typealias Now = @MainActor () -> Int

    private let eventStore: NostrEventStore?
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let now: Now
    private var state = HomeTimelineRuntimeSyncState()

    init(
        eventStore: NostrEventStore?,
        backwardRequestRegistry: HomeTimelineBackwardRequestRegistry,
        now: @escaping Now = { Int(Date().timeIntervalSince1970) }
    ) {
        self.eventStore = eventStore
        self.backwardRequestRegistry = backwardRequestRegistry
        self.now = now
    }

    var isRealtime: Bool {
        state.isRealtime
    }

    var activeRequestCount: Int {
        state.activeRequestCount
    }

    var activeContextCount: Int {
        state.activeContextCount
    }

    func reset(finishingActiveRequestsWith reason: NostrFeedSyncEndReason? = nil) {
        if let reason {
            finishActiveRequests(reason: reason)
        }
        state.reset()
    }

    func prepareForwardSubscriptions(_ subscriptions: Set<RuntimeSubscriptionKey>) {
        state.prepareForwardSubscriptions(subscriptions)
    }

    func invalidateForwardSubscription(_ key: RuntimeSubscriptionKey) {
        state.invalidateForwardSubscription(key)
    }

    func invalidateForwardSubscriptions(relayURL: String) {
        state.invalidateForwardSubscriptions(relayURL: relayURL)
    }

    func registerForwardContext(_ context: HomeFeedRuntimeContext, groupID: String) {
        state.registerForwardContext(context, groupID: groupID)
    }

    func registration(for packet: NostrREQPacket) -> HomeTimelineFeedSyncRegistration? {
        if packet.strategy == .forward,
           HomeTimelineSyncPlanner.isHomeForwardSubscription(packet.subscriptionID) {
            guard let context = state.forwardContext(groupID: packet.groupID) else { return nil }
            let hasSince = packet.filters.contains { $0["since"] != nil }
            return HomeTimelineFeedSyncRegistration(
                context: context,
                direction: .forward,
                purpose: hasSince ? .newer : .initial,
                pendingRequestKey: nil,
                gap: nil
            )
        }

        guard packet.strategy == .backward,
              let requestKey = backwardRequestRegistry.key(for: packet.subscriptionID),
              let request = backwardRequestRegistry.request(for: requestKey),
              let context = request.feedContext
        else { return nil }

        if request.gap != nil {
            return HomeTimelineFeedSyncRegistration(
                context: context,
                direction: .backward,
                purpose: .gap,
                pendingRequestKey: requestKey,
                gap: request.gap
            )
        }
        if request.isOlderPage {
            return HomeTimelineFeedSyncRegistration(
                context: context,
                direction: .backward,
                purpose: .older,
                pendingRequestKey: requestKey,
                gap: nil
            )
        }
        return nil
    }

    func requestID(relayURL: String, subscriptionID: String) -> String? {
        state.requestID(for: key(relayURL: relayURL, subscriptionID: subscriptionID))
    }

    func context(relayURL: String, subscriptionID: String) -> HomeFeedRuntimeContext? {
        state.context(for: key(relayURL: relayURL, subscriptionID: subscriptionID))
    }

    func startRequest(
        _ attempt: NostrRelayRequestAttempt,
        isCurrentFeedContext: (HomeFeedRuntimeContext) -> Bool
    ) -> HomeTimelineFeedSyncRequestStartResult {
        guard let registration = registration(for: attempt.packet) else {
            return HomeTimelineFeedSyncRequestStartResult(
                wasHandled: false,
                isRealtime: state.isRealtime,
                failureMessage: nil
            )
        }
        if attempt.packet.strategy == .forward {
            state.invalidateForwardSubscription(
                key(relayURL: attempt.relayURL, subscriptionID: attempt.packet.subscriptionID)
            )
        }
        guard eventStore != nil else {
            return HomeTimelineFeedSyncRequestStartResult(
                wasHandled: true,
                isRealtime: state.isRealtime,
                failureMessage: nil
            )
        }

        do {
            try beginRequest(attempt, registration: registration)
            if let gap = registration.gap,
               isCurrentFeedContext(registration.context) {
                try? eventStore?.markFeedGap(
                    feedID: registration.context.feedID,
                    revision: registration.context.revision,
                    newerEventID: gap.newerPostID,
                    olderEventID: gap.olderPostID,
                    state: .requested,
                    sourceRequestID: attempt.requestID,
                    at: attempt.startedAt
                )
            }
            return HomeTimelineFeedSyncRequestStartResult(
                wasHandled: true,
                isRealtime: state.isRealtime,
                failureMessage: nil
            )
        } catch {
            return HomeTimelineFeedSyncRequestStartResult(
                wasHandled: true,
                isRealtime: state.isRealtime,
                failureMessage: error.localizedDescription
            )
        }
    }

    func recordRequestInstalled(requestID: String, installedAt: Int) {
        try? eventStore?.markFeedSyncRequestInstalled(
            requestID: requestID,
            at: installedAt
        )
    }

    func handleStreamCompletion(
        relayURL: String,
        subscriptionID: String,
        completion: HomeTimelineFeedSyncStreamCompletion
    ) -> HomeTimelineFeedSyncTransition {
        let window = finishWindow(relayURL: relayURL, subscriptionID: subscriptionID)
        let diagnostic: HomeTimelineFeedSyncDiagnostic
        switch completion {
        case .eose:
            let isHomeForward = HomeTimelineSyncPlanner.isHomeForwardSubscription(subscriptionID)
            recordEOSE(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                window: window
            )
            diagnostic = HomeTimelineFeedSyncDiagnostic(
                relayURL: relayURL,
                kind: .eose,
                subscriptionID: subscriptionID,
                eventCount: window.eventCount,
                newestCreatedAt: isHomeForward ? window.newestCreatedAt : nil,
                oldestCreatedAt: isHomeForward ? window.oldestCreatedAt : nil,
                message: "EOSE received"
            )
        case .closed(let message):
            endRequest(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                reason: .closed,
                message: message,
                window: window
            )
            diagnostic = HomeTimelineFeedSyncDiagnostic(
                relayURL: relayURL,
                kind: Self.syncEventKind(forClosedMessage: message),
                subscriptionID: subscriptionID,
                eventCount: window.eventCount,
                newestCreatedAt: window.newestCreatedAt,
                oldestCreatedAt: window.oldestCreatedAt,
                message: message
            )
        case .timeout(let message):
            endRequest(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                reason: .timeout,
                message: message,
                window: window
            )
            diagnostic = HomeTimelineFeedSyncDiagnostic(
                relayURL: relayURL,
                kind: .timeout,
                subscriptionID: subscriptionID,
                eventCount: window.eventCount,
                newestCreatedAt: window.newestCreatedAt,
                oldestCreatedAt: window.oldestCreatedAt,
                message: message
            )
        }
        return HomeTimelineFeedSyncTransition(
            isRealtime: state.isRealtime,
            diagnostic: diagnostic
        )
    }

    private func beginRequest(
        _ attempt: NostrRelayRequestAttempt,
        registration: HomeTimelineFeedSyncRegistration
    ) throws {
        guard let eventStore else { return }
        let key = key(
            relayURL: attempt.relayURL,
            subscriptionID: attempt.packet.subscriptionID
        )
        if let supersededRequest = state.takeRequest(for: key) {
            try? eventStore.endFeedSyncRequest(
                requestID: supersededRequest.requestID,
                reason: .superseded,
                at: attempt.startedAt,
                eventCount: supersededRequest.window.eventCount,
                observedOldestPosition: supersededRequest.window.oldestCursor,
                observedNewestPosition: supersededRequest.window.newestCursor
            )
        }

        let filters = try attempt.packet.filters.enumerated().map { index, filter in
            try NostrFeedSyncFilterRecord(
                requestID: attempt.requestID,
                filterIndex: index,
                filter: filter
            )
        }
        try eventStore.beginFeedSyncRequest(
            NostrFeedSyncRequestRecord(
                requestID: attempt.requestID,
                feedID: registration.context.feedID,
                feedRevision: registration.context.revision,
                feedSpecificationHash: registration.context.specificationHash,
                relayURL: attempt.relayURL,
                subscriptionID: attempt.packet.subscriptionID,
                direction: registration.direction,
                purpose: registration.purpose,
                requestedAt: attempt.startedAt
            ),
            filters: filters
        )
        state.activateRequest(
            key: key,
            requestID: attempt.requestID,
            context: registration.context
        )
        if let pendingRequestKey = registration.pendingRequestKey {
            backwardRequestRegistry.appendSourceRequestID(
                attempt.requestID,
                for: pendingRequestKey
            )
        }
    }

    private func recordEOSE(
        relayURL: String,
        subscriptionID: String,
        window: RuntimeSyncWindow
    ) {
        let key = key(relayURL: relayURL, subscriptionID: subscriptionID)
        let requestID: String?
        if HomeTimelineSyncPlanner.isHomeForwardSubscription(subscriptionID) {
            // Forward REQはEOSE後もlive subscriptionとして継続するため、
            // revision contextとrequest provenanceをCLOSED/置換まで保持します。
            requestID = state.requestID(for: key)
            state.markForwardEOSE(key)
        } else {
            requestID = state.takeRequest(for: key)?.requestID
        }
        guard let requestID else { return }
        try? eventStore?.recordFeedSyncEOSE(
            requestID: requestID,
            at: now(),
            eventCount: window.eventCount,
            observedOldestPosition: window.oldestCursor,
            observedNewestPosition: window.newestCursor
        )
    }

    private func endRequest(
        relayURL: String,
        subscriptionID: String,
        reason: NostrFeedSyncEndReason,
        message: String?,
        window: RuntimeSyncWindow
    ) {
        let key = key(relayURL: relayURL, subscriptionID: subscriptionID)
        state.invalidateForwardSubscription(key)
        guard let requestID = state.takeRequest(for: key)?.requestID else { return }
        try? eventStore?.endFeedSyncRequest(
            requestID: requestID,
            reason: reason,
            message: message,
            at: now(),
            eventCount: window.eventCount,
            observedOldestPosition: window.oldestCursor,
            observedNewestPosition: window.newestCursor
        )
    }

    func endRequestAttempt(_ end: NostrRelayRequestAttemptEnd) {
        let key = key(relayURL: end.relayURL, subscriptionID: end.subscriptionID)
        state.invalidateForwardSubscription(key)
        let activeRequest = state.takeRequest(for: key, matching: end.requestID)
        let window = activeRequest?.window ?? RuntimeSyncWindow()
        let reason: NostrFeedSyncEndReason
        switch end.reason {
        case .installFailed:
            reason = .installFailed
        case .cancelled:
            reason = .cancelled
        case .superseded:
            reason = .superseded
        }
        try? eventStore?.endFeedSyncRequest(
            requestID: end.requestID,
            reason: reason,
            message: end.message,
            at: end.endedAt,
            eventCount: window.eventCount,
            observedOldestPosition: window.oldestCursor,
            observedNewestPosition: window.newestCursor
        )
    }

    private func finishActiveRequests(reason: NostrFeedSyncEndReason) {
        let finishedAt = now()
        for request in state.activeRequests() {
            try? eventStore?.endFeedSyncRequest(
                requestID: request.requestID,
                reason: reason,
                at: finishedAt,
                eventCount: request.window.eventCount,
                observedOldestPosition: request.window.oldestCursor,
                observedNewestPosition: request.window.newestCursor
            )
        }
    }

    func record(_ event: NostrEvent, relayURL: String, subscriptionID: String) {
        state.record(
            event,
            for: key(relayURL: relayURL, subscriptionID: subscriptionID)
        )
    }

    private func finishWindow(relayURL: String, subscriptionID: String) -> RuntimeSyncWindow {
        state.finishWindow(for: key(relayURL: relayURL, subscriptionID: subscriptionID))
    }

    private static func syncEventKind(forClosedMessage message: String) -> NostrRelaySyncEventKind {
        let normalized = message.lowercased()
        if normalized.contains("auth-required") || normalized.contains("auth required") {
            return .authRequired
        }
        if normalized.contains("payment-required") || normalized.contains("payment required") {
            return .paymentRequired
        }
        return .closed
    }

    private func key(relayURL: String, subscriptionID: String) -> RuntimeSubscriptionKey {
        RuntimeSubscriptionKey(relayURL: relayURL, subscriptionID: subscriptionID)
    }
}
