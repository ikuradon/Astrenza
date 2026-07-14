import AstrenzaCore
import Foundation

struct HomeTimelineRelayStatusSnapshot: Equatable, Sendable {
    let runtimeStates: [String: NostrRelayConnectionState]
    let connectedRelayCount: Int
    let plannedRelayCount: Int
}

struct HomeTimelineRelayStatusTransition: Equatable, Sendable {
    let snapshot: HomeTimelineRelayStatusSnapshot
    let invalidatedRealtimeRelayURL: String?
    let publishesStatusChange: Bool
}

@MainActor
final class HomeTimelineRelayStatusCoordinator {
    typealias Now = @MainActor () -> Int

    private let diagnostics: HomeTimelineRelayDiagnosticsLedger
    private let now: Now
    private var runtimeStates: [String: NostrRelayConnectionState] = [:]

    init(
        diagnostics: HomeTimelineRelayDiagnosticsLedger,
        now: @escaping Now = { Int(Date().timeIntervalSince1970) }
    ) {
        self.diagnostics = diagnostics
        self.now = now
    }

    var events: [NostrRelaySyncEventRecord] {
        diagnostics.events
    }

    func snapshot(resolvedRelays: [String]) -> HomeTimelineRelayStatusSnapshot {
        snapshot(resolvedRelays: resolvedRelays, at: now())
    }

    func reset(resolvedRelays: [String]) -> HomeTimelineRelayStatusSnapshot {
        runtimeStates.removeAll(keepingCapacity: true)
        diagnostics.reset()
        return snapshot(resolvedRelays: resolvedRelays, at: now())
    }

    func replaceEvents(
        _ events: [NostrRelaySyncEventRecord],
        resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusSnapshot {
        diagnostics.replaceEvents(events)
        return snapshot(resolvedRelays: resolvedRelays, at: now())
    }

    func record(
        accountID: String,
        resolvedRelays: [String],
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        subscriptionID: String?,
        eventCount: Int = 0,
        newestCreatedAt: Int? = nil,
        oldestCreatedAt: Int? = nil,
        message: String?
    ) -> HomeTimelineRelayStatusTransition {
        let occurredAt = now()
        diagnostics.record(
            accountID: accountID,
            relayURL: relayURL,
            kind: kind,
            occurredAt: occurredAt,
            subscriptionID: subscriptionID,
            eventCount: eventCount,
            newestCreatedAt: newestCreatedAt,
            oldestCreatedAt: oldestCreatedAt,
            message: message
        )
        return transition(
            resolvedRelays: resolvedRelays,
            at: occurredAt,
            invalidatedRealtimeRelayURL: nil,
            publishesStatusChange: true
        )
    }

    func handleRuntimeStateChange(
        accountID: String?,
        resolvedRelays: [String],
        relayURL: String,
        state: NostrRelayConnectionState
    ) -> HomeTimelineRelayStatusTransition? {
        guard resolvedRelays.contains(relayURL) else { return nil }

        runtimeStates[relayURL] = state
        let occurredAt = now()
        var didRecordDiagnostic = false
        if let accountID,
           let diagnostic = Self.diagnostic(for: state) {
            diagnostics.record(
                accountID: accountID,
                relayURL: relayURL,
                kind: diagnostic.kind,
                occurredAt: occurredAt,
                subscriptionID: nil,
                message: diagnostic.message
            )
            didRecordDiagnostic = true
        }
        return transition(
            resolvedRelays: resolvedRelays,
            at: occurredAt,
            invalidatedRealtimeRelayURL: state == .connected ? nil : relayURL,
            publishesStatusChange: didRecordDiagnostic
        )
    }

    func handleNotice(
        accountID: String?,
        resolvedRelays: [String],
        relayURL: String,
        message: String
    ) -> HomeTimelineRelayStatusTransition? {
        guard let accountID else { return nil }
        return record(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            kind: message.lowercased().contains("timeout") ? .timeout : .partialFailure,
            subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
            message: message
        )
    }

    func handleAuthenticationChallenge(
        accountID: String?,
        resolvedRelays: [String],
        relayURL: String,
        challenge: String
    ) -> HomeTimelineRelayStatusTransition? {
        guard let accountID,
              !diagnostics.hasRecentEvent(
                  relayURL: relayURL,
                  kind: .authRequired,
                  message: challenge
              )
        else { return nil }
        return record(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            kind: .authRequired,
            subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
            message: challenge
        )
    }

    func persistFetchedEvents(_ events: [NostrRelaySyncEventRecord]) async {
        await diagnostics.persistFetchedEvents(events)
    }

    func recordTraffic(_ delta: NostrRelayTrafficDelta) {
        diagnostics.recordTraffic(delta)
    }

    func flushTraffic() {
        diagnostics.flushTraffic()
    }

    private func transition(
        resolvedRelays: [String],
        at occurredAt: Int,
        invalidatedRealtimeRelayURL: String?,
        publishesStatusChange: Bool
    ) -> HomeTimelineRelayStatusTransition {
        HomeTimelineRelayStatusTransition(
            snapshot: snapshot(resolvedRelays: resolvedRelays, at: occurredAt),
            invalidatedRealtimeRelayURL: invalidatedRealtimeRelayURL,
            publishesStatusChange: publishesStatusChange
        )
    }

    private func snapshot(
        resolvedRelays: [String],
        at occurredAt: Int
    ) -> HomeTimelineRelayStatusSnapshot {
        let counts = diagnostics.statusCounts(
            resolvedRelays: resolvedRelays,
            runtimeStates: runtimeStates,
            now: occurredAt
        )
        return HomeTimelineRelayStatusSnapshot(
            runtimeStates: runtimeStates,
            connectedRelayCount: counts.connected,
            plannedRelayCount: counts.planned
        )
    }

    private static func diagnostic(
        for state: NostrRelayConnectionState
    ) -> (kind: NostrRelaySyncEventKind, message: String)? {
        switch state {
        case .connected:
            (.connected, "connected")
        case .waitingForRetry, .retrying:
            (.reconnect, state.rawValue)
        case .error:
            (.partialFailure, state.rawValue)
        case .rejected:
            (.rejected, state.rawValue)
        case .suspended:
            (.suspended, state.rawValue)
        case .initialized, .connecting, .dormant, .terminated:
            nil
        }
    }
}
