import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

let runtimePacketTestAccountID = String(repeating: "a", count: 64)
let runtimePacketTestRelayURL = "wss://relay.example"

@MainActor
struct RuntimePacketFixture {
    let eventStore: NostrEventStore?
    let diagnostics: HomeTimelineRelayDiagnosticsLedger
    let relayStatusCoordinator: HomeTimelineRelayStatusCoordinator
    let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    let coordinator: HomeTimelineRuntimePacketCoordinator

    init(eventStore: NostrEventStore? = nil) {
        let diagnostics = HomeTimelineRelayDiagnosticsLedger(eventStore: eventStore)
        let relayStatusCoordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: diagnostics,
            now: { 200 }
        )
        let feedSyncCoordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: eventStore,
            backwardRequestRegistry: HomeTimelineBackwardRequestRegistry(),
            now: { 200 }
        )
        self.eventStore = eventStore
        self.diagnostics = diagnostics
        self.relayStatusCoordinator = relayStatusCoordinator
        self.feedSyncCoordinator = feedSyncCoordinator
        self.coordinator = HomeTimelineRuntimePacketCoordinator(
            feedSyncCoordinator: feedSyncCoordinator,
            relayStatusCoordinator: relayStatusCoordinator
        )
    }

    func context(
        isActive: Bool = true,
        accountID: String? = runtimePacketTestAccountID,
        resolvedRelays: [String] = [runtimePacketTestRelayURL]
    ) -> HomeTimelineRuntimePacketContext {
        HomeTimelineRuntimePacketContext(
            isActive: isActive,
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            isCurrentFeedContext: { _ in true }
        )
    }

    func prepareForwardRequest(
        suffix: String,
        savesDefinition: Bool = true
    ) throws -> RuntimePacketPreparedRequest {
        let definition = try runtimePacketFeedDefinition()
        if savesDefinition {
            try eventStore?.saveFeedDefinition(definition)
        }
        let packet = runtimePacketForwardPacket(suffix: suffix)
        feedSyncCoordinator.registerForwardContext(
            HomeFeedRuntimeContext(definition: definition),
            groupID: packet.groupID
        )
        feedSyncCoordinator.prepareForwardSubscriptions([
            RuntimeSubscriptionKey(
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: packet.subscriptionID
            )
        ])
        return RuntimePacketPreparedRequest(
            definition: definition,
            packet: packet,
            attempt: NostrRelayRequestAttempt(
                requestID: "request-\(suffix)",
                relayURL: runtimePacketTestRelayURL,
                packet: packet,
                startedAt: 10
            )
        )
    }
}

struct RuntimePacketPreparedRequest {
    let definition: NostrFeedDefinitionRecord
    let packet: NostrREQPacket
    let attempt: NostrRelayRequestAttempt
}

func runtimePacketFeedDefinition() throws -> NostrFeedDefinitionRecord {
    let specification = try JSONEncoder().encode(
        HomeFeedSpecification(authors: [runtimePacketTestAccountID], kinds: [1, 6])
    )
    return NostrFeedDefinitionRecord(
        feedID: "feed:home:\(runtimePacketTestAccountID)",
        accountID: runtimePacketTestAccountID,
        kind: "home",
        specificationJSON: specification,
        specificationHash: "specification",
        revision: 1,
        createdAt: 1,
        updatedAt: 1
    )
}

func runtimePacketForwardPacket(suffix: String) -> NostrREQPacket {
    .forward(
        subscriptionID: "astrenza-home-forward-\(suffix)",
        filters: [[
            "authors": .strings([runtimePacketTestAccountID]),
            "kinds": .ints([1, 6])
        ]]
    )
}

func runtimePacketEvent(idSeed: String, createdAt: Int) -> NostrEvent {
    NostrEvent(
        id: String(repeating: idSeed, count: 64),
        pubkey: runtimePacketTestAccountID,
        createdAt: createdAt,
        kind: 1,
        tags: [],
        content: idSeed,
        sig: String(repeating: "b", count: 128)
    )
}

enum RuntimeProfilePacketCase: CaseIterable, Sendable, CustomTestStringConvertible {
    case requestStarted
    case requestInstalled
    case requestEnded
    case event
    case eose
    case closed
    case timeout
    case backwardCompleted

    var testDescription: String {
        String(describing: self)
    }

    func packet() -> NostrRelayRuntimePacket {
        let subscriptionID = "\(NostrProfileDirectory.groupIDPrefix)-test"
        return switch self {
        case .requestStarted:
            .requestStarted(profileAttempt(subscriptionID: subscriptionID))
        case .requestInstalled:
            .requestInstalled(
                requestID: "profile-request",
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: subscriptionID,
                installedAt: 2
            )
        case .requestEnded:
            .requestEnded(NostrRelayRequestAttemptEnd(
                requestID: "profile-request",
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: subscriptionID,
                reason: .cancelled,
                endedAt: 2
            ))
        case .event:
            .event(
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: subscriptionID,
                event: runtimePacketEvent(idSeed: "1", createdAt: 10)
            )
        case .eose:
            .eose(relayURL: runtimePacketTestRelayURL, subscriptionID: subscriptionID)
        case .closed:
            .closed(
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: subscriptionID,
                message: "closed"
            )
        case .timeout:
            .timeout(
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: subscriptionID,
                message: "timeout"
            )
        case .backwardCompleted:
            .backwardCompleted(profileCompletion(subscriptionID: subscriptionID))
        }
    }

    private func profileAttempt(subscriptionID: String) -> NostrRelayRequestAttempt {
        let packet = NostrREQPacket.forward(
            subscriptionID: subscriptionID,
            filters: [["kinds": .ints([0])]]
        )
        return NostrRelayRequestAttempt(
            requestID: "profile-request",
            relayURL: runtimePacketTestRelayURL,
            packet: packet,
            startedAt: 1
        )
    }

    private func profileCompletion(subscriptionID: String) -> NostrBackwardREQCompletion {
        NostrBackwardREQCompletion(
            groupID: subscriptionID,
            relayURLs: [runtimePacketTestRelayURL],
            subscriptionIDs: [subscriptionID],
            eventCount: 0,
            eoseCount: 1,
            closedCount: 0,
            timeoutCount: 0
        )
    }
}

enum RuntimeStreamCompletionCase: CaseIterable, Sendable, CustomTestStringConvertible {
    case eose
    case closed
    case timeout

    var testDescription: String {
        String(describing: self)
    }

    var isRealtime: Bool {
        self == .eose
    }

    var diagnosticKind: NostrRelaySyncEventKind {
        switch self {
        case .eose: .eose
        case .closed: .closed
        case .timeout: .timeout
        }
    }

    var message: String {
        switch self {
        case .eose: "EOSE received"
        case .closed: "closed"
        case .timeout: "timeout"
        }
    }

    func packet(subscriptionID: String) -> NostrRelayRuntimePacket {
        return switch self {
        case .eose:
            .eose(relayURL: runtimePacketTestRelayURL, subscriptionID: subscriptionID)
        case .closed:
            .closed(
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: subscriptionID,
                message: message
            )
        case .timeout:
            .timeout(
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: subscriptionID,
                message: message
            )
        }
    }
}
