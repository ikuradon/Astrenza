import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline presentation workflow")
@MainActor
struct HomeTimelinePresentationWorkflowTests {
    @Test(
        "Projection anchors preserve account and newest-window behavior",
        arguments: ProjectionAnchorScenario.allCases
    )
    func projectionAnchorBehavior(_ scenario: ProjectionAnchorScenario) {
        let fixture = PresentationFixture()

        fixture.workflow.setRestoreProjectionAnchor(
            scenario.anchorEventID,
            state: fixture.state(account: scenario.hasAccount ? fixture.account : nil),
            effects: fixture.effects
        )

        #expect(fixture.probe.events == scenario.expectedEvents(account: fixture.account))
    }

    @Test("A valid Home viewport is scheduled for its current account feed")
    func validViewportIsScheduled() {
        let fixture = PresentationFixture()
        let viewport = fixture.viewport()

        fixture.workflow.saveViewportState(
            viewport,
            state: fixture.state,
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .scheduleViewportState(
                viewport,
                fixture.feedID,
                fixture.account.pubkey
            )
        ])
    }

    @Test(
        "Every invalid viewport context is rejected",
        arguments: InvalidViewportScenario.allCases
    )
    func invalidViewportIsRejected(_ scenario: InvalidViewportScenario) {
        let fixture = PresentationFixture()

        fixture.workflow.saveViewportState(
            scenario.viewport(fixture: fixture),
            state: scenario.state(fixture: fixture),
            effects: fixture.effects
        )

        #expect(fixture.probe.events.isEmpty)
    }

    @Test(
        "Newest-window updates remain protected by an active restore anchor",
        arguments: NewestWindowScenario.allCases
    )
    func newestWindowProtection(_ scenario: NewestWindowScenario) {
        let fixture = PresentationFixture()

        fixture.workflow.setTimelineAtNewestWindow(
            scenario.requestedValue,
            state: fixture.state(
                account: fixture.account,
                anchorEventID: scenario.anchorEventID
            ),
            effects: fixture.effects
        )

        #expect(fixture.probe.events == scenario.expectedEvents)
    }

    @Test("Scroll completion materializes with the coordinator follow permission")
    func scrollCompletionRoutesMaterialization() {
        let fixture = PresentationFixture()
        fixture.probe.scrollMaterializationPermission = true

        fixture.workflow.setTimelineScrollActive(
            false,
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .setScrollActive(false),
            .materializeEntries(true)
        ])
    }

    @Test("Unread badge dismissal applies the coordinator transition")
    func unreadBadgeDismissalAppliesTransition() {
        let fixture = PresentationFixture()

        fixture.workflow.dismissUnreadBadge(effects: fixture.effects)

        #expect(fixture.probe.events == [
            .dismissUnreadBadge,
            .applyPresentationTransition([.unreadCounts], false)
        ])
    }

    @Test("A visible read transition is applied before persistence is scheduled")
    func visibleReadTransitionSchedulesPersistence() {
        let fixture = PresentationFixture()
        fixture.probe.visibleReadTransition = presentationTransition(
            changes: [.unreadCounts],
            didChangeReadState: true
        )

        fixture.workflow.markMaterializedPostsRead(
            visiblePostIDs: ["visible"],
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .markVisiblePostsRead(["visible"]),
            .applyPresentationTransition([.unreadCounts], true),
            .scheduleReadStateSave
        ])
    }

    @Test("An unchanged visible read state has no application or persistence effects")
    func unchangedVisibleReadStateStopsEffects() {
        let fixture = PresentationFixture()
        fixture.probe.visibleReadTransition = nil

        fixture.workflow.markMaterializedPostsRead(
            visiblePostIDs: ["missing"],
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .markVisiblePostsRead(["missing"])
        ])
    }

    @Test("A newest-window read transition is applied before persistence is scheduled")
    func newestWindowReadTransitionSchedulesPersistence() {
        let fixture = PresentationFixture()
        fixture.probe.newestReadTransition = presentationTransition(
            changes: [.unreadCounts],
            didChangeReadState: true
        )

        fixture.workflow.markNewestMaterializedWindowRead(
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [
            .markNewestWindowRead,
            .applyPresentationTransition([.unreadCounts], true),
            .scheduleReadStateSave
        ])
    }

    @Test("An unavailable newest-window read has no application or persistence effects")
    func unavailableNewestWindowReadStopsEffects() {
        let fixture = PresentationFixture()
        fixture.probe.newestReadTransition = nil

        fixture.workflow.markNewestMaterializedWindowRead(
            effects: fixture.effects
        )

        #expect(fixture.probe.events == [.markNewestWindowRead])
    }
}
