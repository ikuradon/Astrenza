import AstrenzaCore

struct HomeTimelineRuntimePacketContext {
    let isActive: Bool
    let accountID: String?
    let resolvedRelays: [String]
    let isCurrentFeedContext: @MainActor (HomeFeedRuntimeContext) -> Bool
}

enum HomeTimelineRuntimePacketAction: Equatable, Sendable {
    case event(
        relayURL: String,
        subscriptionID: String,
        event: NostrEvent
    )
    case backwardCompleted(NostrBackwardREQCompletion)
}

struct HomeTimelineRuntimePacketApplication: Equatable, Sendable {
    let wasHandled: Bool
    let realtimeState: Bool?
    let relayStatusTransition: HomeTimelineRelayStatusTransition?
    let action: HomeTimelineRuntimePacketAction?
    let requiresPresentationSettlement: Bool

    static let ignored = HomeTimelineRuntimePacketApplication(
        wasHandled: false,
        realtimeState: nil,
        relayStatusTransition: nil,
        action: nil,
        requiresPresentationSettlement: false
    )

    static func handled(
        realtimeState: Bool? = nil,
        relayStatusTransition: HomeTimelineRelayStatusTransition? = nil,
        action: HomeTimelineRuntimePacketAction? = nil,
        requiresPresentationSettlement: Bool = false
    ) -> HomeTimelineRuntimePacketApplication {
        HomeTimelineRuntimePacketApplication(
            wasHandled: true,
            realtimeState: realtimeState,
            relayStatusTransition: relayStatusTransition,
            action: action,
            requiresPresentationSettlement: requiresPresentationSettlement
        )
    }
}

@MainActor
final class HomeTimelineRuntimePacketCoordinator {
    private let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    private let relayStatusCoordinator: HomeTimelineRelayStatusCoordinator

    init(
        feedSyncCoordinator: HomeTimelineFeedSyncCoordinator,
        relayStatusCoordinator: HomeTimelineRelayStatusCoordinator
    ) {
        self.feedSyncCoordinator = feedSyncCoordinator
        self.relayStatusCoordinator = relayStatusCoordinator
    }

    func handle(
        _ packet: NostrRelayRuntimePacket,
        context: HomeTimelineRuntimePacketContext
    ) -> HomeTimelineRuntimePacketApplication {
        guard context.isActive, !Self.isProfileDirectoryPacket(packet) else {
            return .ignored
        }

        switch packet {
        case .stateChanged, .traffic, .notice, .auth:
            return handleRelayPacket(packet, context: context)
        case .requestStarted, .requestInstalled, .requestEnded:
            return handleRequestLifecyclePacket(packet, context: context)
        case .eose, .closed, .timeout:
            return handleStreamPacket(packet, context: context)
        case .event(let relayURL, let subscriptionID, let event):
            return .handled(action: .event(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                event: event
            ))
        case .backwardCompleted(let completion):
            return .handled(action: .backwardCompleted(completion))
        }
    }

    private func handleRelayPacket(
        _ packet: NostrRelayRuntimePacket,
        context: HomeTimelineRuntimePacketContext
    ) -> HomeTimelineRuntimePacketApplication {
        switch packet {
        case .stateChanged(let relayURL, let state):
            return .handled(relayStatusTransition: relayStatusCoordinator.handleRuntimeStateChange(
                accountID: context.accountID,
                resolvedRelays: context.resolvedRelays,
                relayURL: relayURL,
                state: state
            ))
        case .traffic(let delta):
            relayStatusCoordinator.recordTraffic(delta)
            return .handled()
        case .notice(let relayURL, let message):
            return .handled(relayStatusTransition: relayStatusCoordinator.handleNotice(
                accountID: context.accountID,
                resolvedRelays: context.resolvedRelays,
                relayURL: relayURL,
                message: message
            ))
        case .auth(let relayURL, let challenge):
            return .handled(
                relayStatusTransition: relayStatusCoordinator.handleAuthenticationChallenge(
                    accountID: context.accountID,
                    resolvedRelays: context.resolvedRelays,
                    relayURL: relayURL,
                    challenge: challenge
                )
            )
        default:
            return .ignored
        }
    }

    private func handleRequestLifecyclePacket(
        _ packet: NostrRelayRuntimePacket,
        context: HomeTimelineRuntimePacketContext
    ) -> HomeTimelineRuntimePacketApplication {
        switch packet {
        case .requestStarted(let attempt):
            return handleRequestStarted(attempt, context: context)
        case .requestInstalled(let requestID, _, _, let installedAt):
            feedSyncCoordinator.recordRequestInstalled(
                requestID: requestID,
                installedAt: installedAt
            )
            return .handled()
        case .requestEnded(let end):
            feedSyncCoordinator.endRequestAttempt(end)
            let relayStatusTransition: HomeTimelineRelayStatusTransition?
            if end.reason == .installFailed,
               let accountID = context.accountID {
                relayStatusTransition = relayStatusCoordinator.record(
                    accountID: accountID,
                    resolvedRelays: context.resolvedRelays,
                    relayURL: end.relayURL,
                    kind: .partialFailure,
                    subscriptionID: end.subscriptionID,
                    message: end.message ?? "forward REQ installation failed"
                )
            } else {
                relayStatusTransition = nil
            }
            return .handled(
                realtimeState: feedSyncCoordinator.isRealtime,
                relayStatusTransition: relayStatusTransition,
                requiresPresentationSettlement:
                    end.reason == .installFailed &&
                    HomeTimelineSyncPlanner.isHomeForwardSubscription(
                        end.subscriptionID
                    )
            )
        default:
            return .ignored
        }
    }

    private func handleStreamPacket(
        _ packet: NostrRelayRuntimePacket,
        context: HomeTimelineRuntimePacketContext
    ) -> HomeTimelineRuntimePacketApplication {
        switch packet {
        case .eose(let relayURL, let subscriptionID):
            handleStreamCompletion(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                completion: .eose,
                context: context
            )
        case .closed(let relayURL, let subscriptionID, let message):
            handleStreamCompletion(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                completion: .closed(message: message),
                context: context
            )
        case .timeout(let relayURL, let subscriptionID, let message):
            handleStreamCompletion(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                completion: .timeout(message: message),
                context: context
            )
        default:
            .ignored
        }
    }

    private func handleRequestStarted(
        _ attempt: NostrRelayRequestAttempt,
        context: HomeTimelineRuntimePacketContext
    ) -> HomeTimelineRuntimePacketApplication {
        let result = feedSyncCoordinator.startRequest(
            attempt,
            isCurrentFeedContext: context.isCurrentFeedContext
        )
        guard result.wasHandled else { return .handled() }

        let relayStatusTransition: HomeTimelineRelayStatusTransition?
        if let accountID = context.accountID,
           let failureMessage = result.failureMessage {
            relayStatusTransition = relayStatusCoordinator.record(
                accountID: accountID,
                resolvedRelays: context.resolvedRelays,
                relayURL: attempt.relayURL,
                kind: .partialFailure,
                subscriptionID: attempt.packet.subscriptionID,
                message: "feed sync request save failed: \(failureMessage)"
            )
        } else {
            relayStatusTransition = nil
        }
        return .handled(
            realtimeState: result.isRealtime,
            relayStatusTransition: relayStatusTransition
        )
    }

    private func handleStreamCompletion(
        relayURL: String,
        subscriptionID: String,
        completion: HomeTimelineFeedSyncStreamCompletion,
        context: HomeTimelineRuntimePacketContext
    ) -> HomeTimelineRuntimePacketApplication {
        let transition = feedSyncCoordinator.handleStreamCompletion(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            completion: completion
        )
        let relayStatusTransition = context.accountID.map { accountID in
            let diagnostic = transition.diagnostic
            return relayStatusCoordinator.record(
                accountID: accountID,
                resolvedRelays: context.resolvedRelays,
                relayURL: diagnostic.relayURL,
                kind: diagnostic.kind,
                subscriptionID: diagnostic.subscriptionID,
                eventCount: diagnostic.eventCount,
                newestCreatedAt: diagnostic.newestCreatedAt,
                oldestCreatedAt: diagnostic.oldestCreatedAt,
                message: diagnostic.message
            )
        }
        return .handled(
            realtimeState: transition.isRealtime,
            relayStatusTransition: relayStatusTransition,
            requiresPresentationSettlement:
                HomeTimelineSyncPlanner.isHomeForwardSubscription(
                    subscriptionID
                )
        )
    }

    private static func isProfileDirectoryPacket(_ packet: NostrRelayRuntimePacket) -> Bool {
        switch packet {
        case .requestStarted(let attempt):
            NostrProfileDirectory.handles(groupID: attempt.packet.groupID)
        case .requestInstalled(_, _, let subscriptionID, _),
             .event(_, let subscriptionID, _),
             .eose(_, let subscriptionID),
             .closed(_, let subscriptionID, _),
             .timeout(_, let subscriptionID, _):
            NostrProfileDirectory.handles(subscriptionID: subscriptionID)
        case .requestEnded(let end):
            NostrProfileDirectory.handles(subscriptionID: end.subscriptionID)
        case .backwardCompleted(let completion):
            NostrProfileDirectory.handles(groupID: completion.groupID)
        case .stateChanged, .traffic, .notice, .auth:
            false
        }
    }
}
