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
    func appliesPendingSourcesInOrder(_ scenario: PendingEventsScenario) async {
        let account = pendingEventsAccount()
        let probe = PendingEventsProbe()
        let buffer = pendingEventBuffer(eventIDs: scenario.eventIDs)
        let workflow = HomeTimelinePendingEventsWorkflow(buffer: buffer)

        let didApplyPendingEvents = await workflow.apply(
            HomeTimelinePendingEventsState(
                account: account,
                hasPendingProjectionReload: scenario.hasPendingProjectionReload
            ),
            effects: probe.effects
        )

        #expect(didApplyPendingEvents == scenario.expectedResult)
        var expectedEvents: [PendingEventsProbe.Event] = [
            .applyProjectionViewportTransition(.resetToNewest),
            .reloadNewestProjection(account),
            .materializeEntries,
            .waitForPendingPresentation
        ]
        if scenario.hasBufferedEvents {
            expectedEvents.append(.applyPendingEventCountPublication(0))
        }
        expectedEvents += [
            .clearPendingProjectionReload,
            .scheduleLinkPreviewResolution
        ]
        #expect(probe.events == expectedEvents)
        #expect(!workflow.hasBufferedEvents)
    }

    @Test("A missing account prevents every state mutation and side effect")
    func missingAccountStopsApplication() async {
        let probe = PendingEventsProbe()
        let workflow = HomeTimelinePendingEventsWorkflow(
            buffer: pendingEventBuffer(eventIDs: ["event"])
        )

        let didApplyPendingEvents = await workflow.apply(
            HomeTimelinePendingEventsState(
                account: nil,
                hasPendingProjectionReload: true
            ),
            effects: probe.effects
        )

        #expect(!didApplyPendingEvents)
        #expect(probe.events.isEmpty)
        #expect(workflow.hasBufferedEvents)
    }

    @Test("A failed presentation retains every pending source for retry")
    func failedPresentationRetainsPendingSources() async {
        let account = pendingEventsAccount()
        let probe = PendingEventsProbe(presentationResult: false)
        let workflow = HomeTimelinePendingEventsWorkflow(
            buffer: pendingEventBuffer(eventIDs: ["event"])
        )

        let didApply = await workflow.apply(
            HomeTimelinePendingEventsState(
                account: account,
                hasPendingProjectionReload: true
            ),
            effects: probe.effects
        )

        #expect(!didApply)
        #expect(workflow.hasBufferedEvents)
        #expect(probe.events == [
            .applyProjectionViewportTransition(.resetToNewest),
            .reloadNewestProjection(account),
            .materializeEntries,
            .waitForPendingPresentation
        ])
    }

    @Test("Explicit clearing owns buffered state and count publication")
    func explicitClearPublishesCount() {
        let probe = PendingEventsProbe()
        let workflow = HomeTimelinePendingEventsWorkflow(
            buffer: pendingEventBuffer(eventIDs: ["first", "second"])
        )

        #expect(workflow.clear(effects: probe.effects))
        #expect(!workflow.clear(effects: probe.effects))

        #expect(!workflow.hasBufferedEvents)
        #expect(probe.events == [.applyPendingEventCountPublication(0)])
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

    var eventIDs: Set<String> {
        hasBufferedEvents ? ["buffered"] : []
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
        case applyPendingEventCountPublication(Int)
        case clearPendingProjectionReload
        case materializeEntries
        case waitForPendingPresentation
        case scheduleLinkPreviewResolution
    }

    private(set) var events: [Event] = []
    private let presentationResult: Bool

    init(presentationResult: Bool = true) {
        self.presentationResult = presentationResult
    }

    var effects: HomeTimelinePendingEventsEffects {
        HomeTimelinePendingEventsEffects(
            applyProjectionViewportTransition: { [self] transition in
                events.append(.applyProjectionViewportTransition(transition))
            },
            reloadNewestProjection: { [self] account in
                events.append(.reloadNewestProjection(account))
            },
            applyPendingEventCountPublication: { [self] publication in
                events.append(.applyPendingEventCountPublication(
                    publication.count
                ))
            },
            clearPendingProjectionReload: { [self] in
                events.append(.clearPendingProjectionReload)
            },
            materializeEntries: { [self] in
                events.append(.materializeEntries)
            },
            waitForPendingPresentation: { [self] in
                events.append(.waitForPendingPresentation)
                return presentationResult
            },
            scheduleLinkPreviewResolution: { [self] in
                events.append(.scheduleLinkPreviewResolution)
            }
        )
    }
}

@MainActor
private func pendingEventBuffer(
    eventIDs: Set<String>
) -> HomeTimelinePendingEventBuffer {
    let buffer = HomeTimelinePendingEventBuffer()
    buffer.replaceEventIDs(eventIDs) { _ in }
    return buffer
}

private func pendingEventsAccount() -> NostrAccount {
    NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "pending-events",
        readOnly: true
    )
}
