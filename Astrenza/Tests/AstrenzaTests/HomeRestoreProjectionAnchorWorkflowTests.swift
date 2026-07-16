import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home restore projection anchor workflow")
@MainActor
struct HomeRestoreProjectionAnchorWorkflowTests {
    @Test("A missing anchor does not start restoration")
    func ignoresMissingAnchor() {
        let fixture = RestoreProjectionAnchorFixture(anchorEventID: nil)

        fixture.workflow.restoreIfPossible(account: fixture.account)

        #expect(fixture.target.events.isEmpty)
    }

    @Test("A failed projection reload does not materialize")
    func stopsAfterFailedReload() {
        let fixture = RestoreProjectionAnchorFixture()

        fixture.workflow.restoreIfPossible(account: fixture.account)
        fixture.target.completeReload(didReload: false)

        #expect(fixture.target.events == [
            .reloadProjection(
                accountID: fixture.account.pubkey,
                anchorEventID: fixture.anchorEventID,
                mergesCurrentWindow: false
            )
        ])
    }

    @Test("An account change invalidates a completed reload")
    func rejectsReloadForStaleAccount() {
        let fixture = RestoreProjectionAnchorFixture()

        fixture.workflow.restoreIfPossible(account: fixture.account)
        fixture.target.account = fixture.replacementAccount
        fixture.target.completeReload(didReload: true)

        #expect(fixture.target.events.count == 1)
    }

    @Test("An anchor change invalidates a completed reload")
    func rejectsReloadForStaleAnchor() {
        let fixture = RestoreProjectionAnchorFixture()

        fixture.workflow.restoreIfPossible(account: fixture.account)
        fixture.target.restoreProjectionAnchorEventID = "replacement-anchor"
        fixture.target.completeReload(didReload: true)

        #expect(fixture.target.events.count == 1)
    }

    @Test("A restored nonempty projection publishes follow-up effects in order")
    func completesNonemptyRestoration() {
        let fixture = RestoreProjectionAnchorFixture()

        fixture.workflow.restoreIfPossible(account: fixture.account)
        fixture.target.completeReload(didReload: true)
        fixture.target.completeMaterialization(hasEntries: true)

        #expect(fixture.target.events == [
            .reloadProjection(
                accountID: fixture.account.pubkey,
                anchorEventID: fixture.anchorEventID,
                mergesCurrentWindow: false
            ),
            .materialize(allowsRealtimeFollow: false),
            .scheduleLinkPreviewResolution,
            .setPhase(.loaded)
        ])
    }

    @Test("An empty restored projection resolves previews without setting loaded")
    func keepsLoadingForEmptyRestoration() {
        let fixture = RestoreProjectionAnchorFixture()

        fixture.workflow.restoreIfPossible(account: fixture.account)
        fixture.target.completeReload(didReload: true)
        fixture.target.completeMaterialization(hasEntries: false)

        #expect(fixture.target.events == [
            .reloadProjection(
                accountID: fixture.account.pubkey,
                anchorEventID: fixture.anchorEventID,
                mergesCurrentWindow: false
            ),
            .materialize(allowsRealtimeFollow: false),
            .scheduleLinkPreviewResolution
        ])
    }

    @Test("The workflow does not retain its target")
    func doesNotRetainTarget() throws {
        let account = RestoreProjectionAnchorFixture.makeAccount(
            pubkeyCharacter: "a"
        )
        var target: RestoreProjectionAnchorTargetSpy? =
            RestoreProjectionAnchorTargetSpy(
                account: account,
                anchorEventID: "anchor"
            )
        weak let weakTarget = target
        let workflow = HomeRestoreProjectionAnchorWorkflow(
            target: try #require(target)
        )

        target = nil

        #expect(weakTarget == nil)
        workflow.restoreIfPossible(account: account)
    }
}

@MainActor
private struct RestoreProjectionAnchorFixture {
    let anchorEventID: String?
    let account: NostrAccount
    let replacementAccount: NostrAccount
    let target: RestoreProjectionAnchorTargetSpy
    let workflow: HomeRestoreProjectionAnchorWorkflow

    init(anchorEventID: String? = "anchor") {
        let account = Self.makeAccount(pubkeyCharacter: "a")
        let target = RestoreProjectionAnchorTargetSpy(
            account: account,
            anchorEventID: anchorEventID
        )
        self.anchorEventID = anchorEventID
        self.account = account
        replacementAccount = Self.makeAccount(pubkeyCharacter: "b")
        self.target = target
        workflow = HomeRestoreProjectionAnchorWorkflow(target: target)
    }

    static func makeAccount(pubkeyCharacter: Character) -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: pubkeyCharacter, count: 64),
            displayIdentifier: "restore-projection",
            readOnly: true
        )
    }
}

@MainActor
private final class RestoreProjectionAnchorTargetSpy:
    HomeRestoreProjectionAnchorTarget {
    enum Event: Equatable {
        case reloadProjection(
            accountID: String,
            anchorEventID: String?,
            mergesCurrentWindow: Bool
        )
        case materialize(allowsRealtimeFollow: Bool)
        case scheduleLinkPreviewResolution
        case setPhase(NostrHomeTimelinePhase)
        case setRealtime(Bool)
    }

    var account: NostrAccount?
    var restoreProjectionAnchorEventID: String?
    private(set) var events: [Event] = []
    private var reloadCompletion: HomeTimelineMaterializationCoordinating
        .ProjectionReloadHandler?
    private var materializationTransition:
        HomeTimelineMaterializationCoordinating.TransitionHandler?

    init(account: NostrAccount, anchorEventID: String?) {
        self.account = account
        restoreProjectionAnchorEventID = anchorEventID
    }

    func reloadProjectionWindow(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    ) {
        events.append(.reloadProjection(
            accountID: account.pubkey,
            anchorEventID: anchorEventID,
            mergesCurrentWindow: mergingWithCurrentWindow
        ))
        reloadCompletion = onCompletion
    }

    func materializeEntries(
        allowsRealtimeFollow: Bool,
        onTransition: HomeTimelineMaterializationCoordinating
            .TransitionHandler?
    ) {
        events.append(.materialize(
            allowsRealtimeFollow: allowsRealtimeFollow
        ))
        materializationTransition = onTransition
    }

    func scheduleLinkPreviewResolution() {
        events.append(.scheduleLinkPreviewResolution)
    }

    func applyActivityIntent(_ intent: HomeTimelineActivityIntent) {
        switch intent {
        case .setPhase(let phase):
            events.append(.setPhase(phase))
        case .setRealtime(let isRealtime):
            events.append(.setRealtime(isRealtime))
        }
    }

    func completeReload(didReload: Bool) {
        let completion = reloadCompletion
        reloadCompletion = nil
        completion?(didReload)
    }

    func completeMaterialization(hasEntries: Bool) {
        let transition = materializationTransition
        materializationTransition = nil
        transition?(presentationTransition(hasEntries: hasEntries))
    }

    private func presentationTransition(
        hasEntries: Bool
    ) -> HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: HomeTimelinePresentationSnapshot(
                entries: hasEntries
                    ? [.deleted(TimelineDeletedEntry(id: "restored"))]
                    : [],
                filterStatus: TimelineFilterStatus(),
                materializedUnreadCount: 0,
                visibleUnreadBadgeCount: 0,
                resolvedContentRevision: 1,
                realtimeFollowSourceRevision: nil
            ),
            changes: [.entries],
            didChangeReadState: false
        )
    }
}
