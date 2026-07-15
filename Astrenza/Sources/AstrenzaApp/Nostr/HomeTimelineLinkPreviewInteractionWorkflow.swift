import AstrenzaCore

@MainActor
protocol HomeTimelineLinkPreviewScheduling: AnyObject {
    @discardableResult
    func schedule(
        scopeID: String,
        policy: NostrSyncPolicy,
        didUpdate: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor (_ message: String) -> Void
    ) -> Bool
}

extension HomeTimelineLinkPreviewCoordinator: HomeTimelineLinkPreviewScheduling {}

struct HomeTimelineLinkPreviewInteractionState: Equatable, Sendable {
    let accountID: String?
    let resolvedRelays: [String]
    let policy: NostrSyncPolicy
}

enum HomeTimelineLinkPreviewStoreAction: Equatable, Sendable {
    case applyRelayStatusTransition(HomeTimelineRelayStatusTransition)
}

struct HomeLinkPreviewInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineLinkPreviewStoreAction
    ) -> Void
    typealias UpdateEffect = @MainActor @Sendable () -> Void

    let didUpdate: UpdateEffect
    let apply: ApplicationEffect
}

private struct HomeTimelineLinkPreviewDiagnostic:
    Equatable,
    HomeTimelineRelayStatusDiagnostic {
    let relayURL = "link-preview"
    let message: String
}

@MainActor
final class HomeLinkPreviewInteractionWorkflow {
    private let linkPreviews: any HomeTimelineLinkPreviewScheduling
    private let relayStatus: any HomeTimelineRelayStatusRecording

    init(
        linkPreviews: any HomeTimelineLinkPreviewScheduling,
        relayStatus: any HomeTimelineRelayStatusRecording
    ) {
        self.linkPreviews = linkPreviews
        self.relayStatus = relayStatus
    }

    @discardableResult
    func schedule(
        state: HomeTimelineLinkPreviewInteractionState,
        effects: HomeLinkPreviewInteractionEffects
    ) -> Bool {
        guard let accountID = state.accountID else { return false }
        return linkPreviews.schedule(
            scopeID: accountID,
            policy: state.policy,
            didUpdate: effects.didUpdate,
            didFail: { message in
                guard let transition = self.relayStatus.recordDiagnostic(
                    HomeTimelineLinkPreviewDiagnostic(
                        message: "link preview save failed: \(message)"
                    ),
                    accountID: accountID,
                    resolvedRelays: state.resolvedRelays
                ) else { return }
                effects.apply(.applyRelayStatusTransition(transition))
            }
        )
    }
}
