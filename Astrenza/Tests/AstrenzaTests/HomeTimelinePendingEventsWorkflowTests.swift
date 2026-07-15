import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline pending events workflow")
@MainActor
struct HomeTimelinePendingEventsWorkflowTests {
    @Test(
        "Every pending source preserves newest-window application order",
        arguments: PendingEventsScenario.allCases
    )
    func appliesPendingSourcesInOrder(_ scenario: PendingEventsScenario) {
        let account = pendingEventsAccount()
        let probe = PendingEventsProbe()
        let workflow = HomeTimelinePendingEventsWorkflow()

        let didApplyPendingEvents = workflow.apply(
            HomeTimelinePendingEventsState(
                account: account,
                hasBufferedEvents: scenario.hasBufferedEvents,
                hasPendingProjectionReload: scenario.hasPendingProjectionReload
            ),
            effects: probe.effects
        )

        #expect(didApplyPendingEvents == scenario.expectedResult)
        #expect(probe.events == [
            .applyProjectionViewportTransition(.resetToNewest),
            .reloadNewestProjection(account),
            .clearBufferedEvents,
            .clearPendingProjectionReload,
            .materializeEntries,
            .scheduleLinkPreviewResolution
        ])
    }

    @Test("A missing account prevents every state mutation and side effect")
    func missingAccountStopsApplication() {
        let probe = PendingEventsProbe()
        let workflow = HomeTimelinePendingEventsWorkflow()

        let didApplyPendingEvents = workflow.apply(
            HomeTimelinePendingEventsState(
                account: nil,
                hasBufferedEvents: true,
                hasPendingProjectionReload: true
            ),
            effects: probe.effects
        )

        #expect(!didApplyPendingEvents)
        #expect(probe.events.isEmpty)
    }
}

enum PendingEventsScenario: CaseIterable, Sendable {
    case none
    case buffered
    case projectionReload
    case both

    var hasBufferedEvents: Bool {
        self == .buffered || self == .both
    }

    var hasPendingProjectionReload: Bool {
        self == .projectionReload || self == .both
    }

    var expectedResult: Bool {
        self != .none
    }
}

extension PendingEventsScenario: CustomTestStringConvertible {
    var testDescription: String {
        switch self {
        case .none:
            "no pending source"
        case .buffered:
            "buffered events"
        case .projectionReload:
            "projection reload"
        case .both:
            "both pending sources"
        }
    }
}

@MainActor
private final class PendingEventsProbe {
    enum Event: Equatable {
        case applyProjectionViewportTransition(
            HomeTimelineProjectionViewportTransition
        )
        case reloadNewestProjection(NostrAccount)
        case clearBufferedEvents
        case clearPendingProjectionReload
        case materializeEntries
        case scheduleLinkPreviewResolution
    }

    private(set) var events: [Event] = []

    var effects: HomeTimelinePendingEventsEffects {
        HomeTimelinePendingEventsEffects(
            applyProjectionViewportTransition: { [self] transition in
                events.append(.applyProjectionViewportTransition(transition))
            },
            reloadNewestProjection: { [self] account in
                events.append(.reloadNewestProjection(account))
            },
            clearBufferedEvents: { [self] in
                events.append(.clearBufferedEvents)
            },
            clearPendingProjectionReload: { [self] in
                events.append(.clearPendingProjectionReload)
            },
            materializeEntries: { [self] in
                events.append(.materializeEntries)
            },
            scheduleLinkPreviewResolution: { [self] in
                events.append(.scheduleLinkPreviewResolution)
            }
        )
    }
}

private func pendingEventsAccount() -> NostrAccount {
    NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "pending-events",
        readOnly: true
    )
}
