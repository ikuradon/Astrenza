import Testing
@testable import Astrenza

@MainActor
@Suite("Home timeline presentation coordinator")
struct HomeTimelinePresentationCoordinatorTests {
    @Test("Materialization publishes entries, filter, revision, and realtime follow together")
    func materializationPublishesOnePresentationTransition() throws {
        let coordinator = HomeTimelinePresentationCoordinator()
        let pass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: true))
        let first = entry("first")
        let second = entry("second")
        let filterStatus = TimelineFilterStatus(activeRuleCount: 2, warningMatchCount: 1)

        let transition = try #require(coordinator.apply(
            HomeTimelineMaterializedSnapshot(
                entries: [first, second],
                filterStatus: filterStatus,
                renderFingerprint: [1, 2]
            ),
            pass: pass
        ))

        #expect(transition.changes.contains(.entries))
        #expect(transition.changes.contains(.filterStatus))
        #expect(transition.changes.contains(.resolvedContentRevision))
        #expect(transition.changes.contains(.realtimeFollowSourceRevision))
        #expect(!transition.changes.contains(.unreadCounts))
        #expect(transition.snapshot.entries.map(\.id) == [first.id, second.id])
        #expect(transition.snapshot.filterStatus == filterStatus)
        #expect(transition.snapshot.resolvedContentRevision == 1)
        #expect(transition.snapshot.realtimeFollowSourceRevision == 1)
        #expect(transition.snapshot.materializedUnreadCount == 0)
    }

    @Test("An unchanged render fingerprint does not republish presentation state")
    func unchangedFingerprintDoesNotRepublish() throws {
        let coordinator = HomeTimelinePresentationCoordinator()
        let materialized = HomeTimelineMaterializedSnapshot(
            entries: [entry("first")],
            filterStatus: TimelineFilterStatus(),
            renderFingerprint: [1]
        )
        let firstPass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: false))
        _ = try #require(coordinator.apply(materialized, pass: firstPass))
        let secondPass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: true))

        let duplicate = try #require(coordinator.apply(
            materialized,
            pass: secondPass
        ))

        #expect(duplicate.changes.isEmpty)
        #expect(duplicate.snapshot.resolvedContentRevision == 1)
        #expect(duplicate.snapshot.realtimeFollowSourceRevision == nil)
    }

    @Test("A filter-only update advances revision and revokes realtime follow")
    func filterOnlyUpdateAdvancesRevisionAndRevokesFollow() throws {
        let coordinator = HomeTimelinePresentationCoordinator()
        let firstPass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: true))
        _ = try #require(coordinator.apply(
            HomeTimelineMaterializedSnapshot(
                entries: [entry("first")],
                filterStatus: TimelineFilterStatus(),
                renderFingerprint: [1]
            ),
            pass: firstPass
        ))
        let secondPass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: false))

        let transition = try #require(coordinator.apply(
            HomeTimelineMaterializedSnapshot(
                entries: [entry("first")],
                filterStatus: TimelineFilterStatus(activeRuleCount: 1),
                renderFingerprint: [1]
            ),
            pass: secondPass
        ))

        #expect(!transition.changes.contains(.entries))
        #expect(transition.changes.contains(.filterStatus))
        #expect(transition.changes.contains(.resolvedContentRevision))
        #expect(transition.changes.contains(.realtimeFollowSourceRevision))
        #expect(transition.snapshot.resolvedContentRevision == 2)
        #expect(transition.snapshot.realtimeFollowSourceRevision == nil)
    }

    @Test("Unread badge actions remain generation scoped after materialization")
    func unreadActionsRemainGenerationScoped() throws {
        let coordinator = HomeTimelinePresentationCoordinator()
        let initialPass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: false))
        _ = try #require(coordinator.apply(
            HomeTimelineMaterializedSnapshot(
                entries: [entry("old")],
                filterStatus: TimelineFilterStatus(),
                renderFingerprint: [1]
            ),
            pass: initialPass
        ))
        let newPass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: false))
        let firstUnread = try #require(coordinator.apply(
            HomeTimelineMaterializedSnapshot(
                entries: [entry("new-1"), entry("old")],
                filterStatus: TimelineFilterStatus(),
                renderFingerprint: [2, 1]
            ),
            pass: newPass
        ))
        #expect(firstUnread.snapshot.materializedUnreadCount == 1)
        #expect(firstUnread.snapshot.visibleUnreadBadgeCount == 1)

        let dismissed = coordinator.dismissUnreadBadge()
        #expect(dismissed.snapshot.materializedUnreadCount == 1)
        #expect(dismissed.snapshot.visibleUnreadBadgeCount == 0)

        let nextPass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: false))
        let secondUnread = try #require(coordinator.apply(
            HomeTimelineMaterializedSnapshot(
                entries: [entry("new-2"), entry("new-1"), entry("old")],
                filterStatus: TimelineFilterStatus(),
                renderFingerprint: [3, 2, 1]
            ),
            pass: nextPass
        ))
        #expect(secondUnread.snapshot.materializedUnreadCount == 2)
        #expect(secondUnread.snapshot.visibleUnreadBadgeCount == 2)

        let visibleRead = try #require(coordinator.markVisiblePostsRead(["new-2"]))
        #expect(visibleRead.didChangeReadState)
        #expect(visibleRead.snapshot.materializedUnreadCount == 1)

        let newestRead = try #require(coordinator.markNewestWindowRead())
        #expect(newestRead.didChangeReadState)
        #expect(newestRead.snapshot.materializedUnreadCount == 0)
        #expect(newestRead.snapshot.visibleUnreadBadgeCount == 0)
    }

    @Test("Restored read boundaries drive later read-state mutations")
    func restoredReadBoundaryDrivesLaterMutations() throws {
        let coordinator = HomeTimelinePresentationCoordinator()
        let pass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: false))
        _ = try #require(coordinator.apply(
            HomeTimelineMaterializedSnapshot(
                entries: [entry("new-1"), entry("new-2"), entry("old")],
                filterStatus: TimelineFilterStatus(),
                renderFingerprint: [1, 2, 3]
            ),
            pass: pass
        ))

        let restored = coordinator.restoreReadBoundary(postID: "old")
        #expect(restored.snapshot.materializedUnreadCount == 2)
        #expect(coordinator.readBoundaryPostID == "old")
        #expect(coordinator.markVisiblePostsRead(["missing"]) == nil)

        let read = try #require(coordinator.markVisiblePostsRead(["new-1"]))
        #expect(read.didChangeReadState)
        #expect(read.snapshot.materializedUnreadCount == 1)
    }

    @Test("Reset cancels scheduling and clears presentation while preserving revision monotonicity")
    func resetPreservesRevisionMonotonicity() throws {
        let scheduler = HomeTimelineMaterializationScheduler(
            defaultDelayNanoseconds: 1_000_000_000
        )
        let coordinator = HomeTimelinePresentationCoordinator(scheduler: scheduler)
        let pass = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: true))
        _ = try #require(coordinator.apply(
            HomeTimelineMaterializedSnapshot(
                entries: [entry("first")],
                filterStatus: TimelineFilterStatus(activeRuleCount: 1),
                renderFingerprint: [1]
            ),
            pass: pass
        ))
        coordinator.schedule(materialize: { _ in })
        #expect(coordinator.hasPendingMaterialization)

        let reset = coordinator.reset()

        #expect(reset.snapshot.entries.isEmpty)
        #expect(reset.snapshot.filterStatus == TimelineFilterStatus())
        #expect(reset.snapshot.materializedUnreadCount == 0)
        #expect(reset.snapshot.visibleUnreadBadgeCount == 0)
        #expect(reset.snapshot.resolvedContentRevision == 1)
        #expect(reset.snapshot.realtimeFollowSourceRevision == nil)
        #expect(!coordinator.hasPendingMaterialization)
    }

    @Test("Projection reload requests remain part of the materialization pass")
    func projectionReloadRequestsRemainInPass() throws {
        let coordinator = HomeTimelinePresentationCoordinator()
        coordinator.requestNewestProjectionReload()

        let first = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: false))
        #expect(first.shouldReloadNewestProjection)

        coordinator.clearNewestProjectionReload()
        let second = try #require(coordinator.beginMaterialization(allowsRealtimeFollow: false))
        #expect(!second.shouldReloadNewestProjection)
    }

    @Test("A superseded materialization pass cannot publish stale entries")
    func supersededPassCannotPublish() throws {
        let coordinator = HomeTimelinePresentationCoordinator()
        let stalePass = try #require(coordinator.beginMaterialization(
            allowsRealtimeFollow: true
        ))
        let currentPass = try #require(coordinator.beginMaterialization(
            allowsRealtimeFollow: false
        ))
        let staleSnapshot = HomeTimelineMaterializedSnapshot(
            entries: [entry("stale")],
            filterStatus: TimelineFilterStatus(),
            renderFingerprint: [1]
        )
        let currentSnapshot = HomeTimelineMaterializedSnapshot(
            entries: [entry("current")],
            filterStatus: TimelineFilterStatus(),
            renderFingerprint: [2]
        )

        #expect(coordinator.apply(staleSnapshot, pass: stalePass) == nil)
        let applied = try #require(coordinator.apply(
            currentSnapshot,
            pass: currentPass
        ))

        #expect(applied.snapshot.entries.map(\.id) == ["current"])
        #expect(applied.snapshot.realtimeFollowSourceRevision == nil)
    }

    private func entry(_ id: String) -> TimelineFeedEntry {
        .post(TimelinePost(
            id: id,
            author: .unresolved(pubkey: String(repeating: "a", count: 64)),
            avatar: AvatarStyle(
                primary: .astrenzaAccent,
                secondary: .astrenzaAttachmentBackground,
                symbolName: "person.fill",
                pictureState: .metadataPending,
                placeholderSeed: id
            ),
            body: id,
            createdAt: TimelineMockClock.referenceNow,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        ))
    }
}
