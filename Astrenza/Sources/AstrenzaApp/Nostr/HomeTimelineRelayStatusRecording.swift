import AstrenzaCore

struct HomeTimelineRelayStatusRecord: Equatable, Sendable {
    let accountID: String
    let resolvedRelays: [String]
    let relayURL: String
    let kind: NostrRelaySyncEventKind
    let subscriptionID: String?
    let eventCount: Int
    let newestCreatedAt: Int?
    let oldestCreatedAt: Int?
    let message: String?
}

@MainActor
protocol HomeTimelineRelayStatusRecording: AnyObject {
    func record(
        _ record: HomeTimelineRelayStatusRecord
    ) -> HomeTimelineRelayStatusTransition
}

protocol HomeTimelineRelayStatusDiagnostic: Sendable {
    var relayURL: String { get }
    var kind: NostrRelaySyncEventKind { get }
    var subscriptionID: String? { get }
    var message: String { get }
}

extension HomeTimelineRelayStatusDiagnostic {
    var kind: NostrRelaySyncEventKind { .partialFailure }
    var subscriptionID: String? { nil }
}

extension HomeTimelineRuntimeSetupDiagnostic:
    HomeTimelineRelayStatusDiagnostic {}
extension HomeTimelineRuntimeEventDiagnostic:
    HomeTimelineRelayStatusDiagnostic {}
extension HomeTimelineRuntimeApplicationDiagnostic:
    HomeTimelineRelayStatusDiagnostic {}
extension HomeTimelineLoadDiagnostic:
    HomeTimelineRelayStatusDiagnostic {}
extension HomeTimelineBackwardRequestDiagnostic:
    HomeTimelineRelayStatusDiagnostic {}
extension HomeTimelineBackwardAppDiagnostic:
    HomeTimelineRelayStatusDiagnostic {}

extension HomeTimelineRelayStatusRecording {
    func recordDiagnostic<Diagnostic>(
        _ diagnostic: Diagnostic,
        accountID: String?,
        resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusTransition?
    where Diagnostic: HomeTimelineRelayStatusDiagnostic {
        guard let accountID else { return nil }
        return record(HomeTimelineRelayStatusRecord(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: diagnostic.relayURL,
            kind: diagnostic.kind,
            subscriptionID: diagnostic.subscriptionID,
            eventCount: 0,
            newestCreatedAt: nil,
            oldestCreatedAt: nil,
            message: diagnostic.message
        ))
    }
}
