import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline presentation workflow")
@MainActor
struct HomeTimelinePresentationWorkflowTests {
    @Test("Store-facing scheduling state crosses the presentation boundary")
    func interactionStatePreservesCoordinatorValues() {
        let fixture = PresentationFixture()
        fixture.probe.hasPendingNewestProjectionReload = true
        fixture.probe.readBoundaryPostID = "boundary"
        fixture.probe.defaultDelayNanoseconds = 42

        #expect(fixture.workflow.interactionState ==
            HomeTimelinePresentationInteractionState(
                hasPendingNewestProjectionReload: true,
                readBoundaryPostID: "boundary",
                defaultDelayNanoseconds: 42
            ))
    }

    @Test("Projection reload and read-boundary commands remain ordered")
    func routesProjectionStateCommands() {
        let fixture = PresentationFixture()

        fixture.workflow.requestNewestProjectionReload()
        fixture.workflow.clearNewestProjectionReload()
        let transition = fixture.workflow.restoreReadBoundary(
            postID: "boundary"
        )

        #expect(transition.changes == [.unreadCounts])
        #expect(fixture.probe.events == [
            .requestNewestProjectionReload,
            .clearNewestProjectionReload,
            .restoreReadBoundary("boundary")
        ])
    }

    @Test("Scheduled materialization preserves delay and follow permission")
    func routesMaterializationScheduling() {
        let fixture = PresentationFixture()
        fixture.probe.scheduledMaterializationPermission = true

        fixture.workflow.scheduleMaterialization(
            delayNanoseconds: 123,
            allowsRealtimeFollow: false,
            materialize: fixture.effects.materializeEntries
        )

        #expect(fixture.probe.events == [
            .scheduleMaterialization(123, false),
            .materializeEntries(true)
        ])
    }

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
            .scheduleViewportState(viewport)
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

    @Test("Link preview scheduling preserves account, policy, and callbacks")
    func linkPreviewSchedulingRoutesRequestAndCallbacks() {
        let fixture = PresentationFixture(linkPreviewScheduleResult: true)

        let scheduled = fixture.workflow.scheduleLinkPreviewResolution(
            state: fixture.linkPreviewState,
            effects: fixture.linkPreviewEffects.effects
        )
        fixture.linkPreviews.completeUpdate()
        fixture.linkPreviews.fail("persistence failed")

        #expect(scheduled)
        #expect(fixture.linkPreviews.schedules == [
            PresentationLinkPreviewSchedule(
                scopeID: fixture.account.pubkey,
                policy: .default()
            )
        ])
        #expect(fixture.linkPreviewEffects.events == [
            .updated,
            .failed("persistence failed")
        ])
    }

    @Test("Link preview scheduling rejects a missing account")
    func linkPreviewSchedulingRequiresAccount() {
        let fixture = PresentationFixture()

        let scheduled = fixture.workflow.scheduleLinkPreviewResolution(
            state: HomeTimelineLinkPreviewInteractionState(
                accountID: nil,
                policy: .default()
            ),
            effects: fixture.linkPreviewEffects.effects
        )

        #expect(!scheduled)
        #expect(fixture.linkPreviews.schedules.isEmpty)
        #expect(fixture.linkPreviewEffects.events.isEmpty)
    }
}
