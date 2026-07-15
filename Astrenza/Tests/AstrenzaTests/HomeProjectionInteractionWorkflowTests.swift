import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline projection interaction workflow")
@MainActor
struct HomeProjectionInteractionWorkflowTests {
    @Test("Startup viewport restoration does not require an activated projection")
    func startupViewportRestorationPrecedesProjectionActivation() {
        let account = account(character: "a")
        let restored = viewport(accountID: account.pubkey)
        let viewportStateRestorer = ViewportStateRestorerSpy(result: restored)
        let workflow = makeWorkflow(
            projection: ProjectionInteractionSpy(definition: nil),
            viewportStateRestorer: viewportStateRestorer
        )

        #expect(workflow.restoredViewportState(
            accountID: account.pubkey,
            timelineKey: "home"
        ) == restored)
        #expect(workflow.restoredViewportState(
            accountID: account.pubkey,
            timelineKey: "lists"
        ) == nil)
        #expect(viewportStateRestorer.accountID == account.pubkey)
        #expect(viewportStateRestorer.timelineKey == "home")
        #expect(viewportStateRestorer.callCount == 1)
    }

    @Test("Projection lifecycle and materialization cross one typed boundary")
    func routesProjectionLifecycleAndMaterialization() {
        let account = account(character: "a")
        let definition = definition(accountID: account.pubkey)
        let projection = ProjectionInteractionSpy(
            definition: definition,
            isCurrentResult: true
        )
        let materialization = MaterializationInteractionSpy(
            reloadNewestResult: true,
            reloadResult: true
        )
        let workflow = makeWorkflow(
            projection: projection,
            materialization: materialization,
            timestamp: 654
        )
        let liveEvent = event(accountID: account.pubkey)
        let context = HomeFeedRuntimeContext(definition: definition)
        let reloadProbe = ProjectionReloadProbe()
        let request = HomeTimelineMaterializationRequest(
            account: account,
            nip05Resolutions: [:],
            profileResolutionStates: [:],
            policy: .default(networkType: .unknown, lowPowerMode: false),
            allowsRealtimeFollow: true
        )

        workflow.prepareDefinition(
            account: account,
            followedPubkeys: [account.pubkey],
            liveEvents: [liveEvent]
        )
        #expect(workflow.isCurrent(context, accountID: account.pubkey))
        routeProjectionReloads(through: workflow, account: account, probe: reloadProbe)
        workflow.materialize(request) { _ in }

        #expect(projection.prewarmedAccountID == account.pubkey)
        #expect(projection.prewarmedFollowedPubkeys == [account.pubkey])
        #expect(projection.prewarmedLiveEventIDs == [liveEvent.id])
        #expect(projection.prewarmedAt == 654)
        #expect(projection.currentContext == context)
        #expect(projection.currentAccountID == account.pubkey)
        #expect(materialization.newestAccountID == account.pubkey)
        #expect(materialization.reloadAccountID == account.pubkey)
        #expect(materialization.reloadAnchorEventID == "anchor")
        #expect(materialization.reloadMergesCurrentWindow)
        #expect(reloadProbe.results == [true, true])
        #expect(materialization.materializationAccountID == account.pubkey)
        #expect(materialization.allowsRealtimeFollow)
    }

    @Test("Materialization cancellation crosses the interaction boundary")
    func routesMaterializationCancellation() {
        let materialization = MaterializationInteractionSpy()
        let workflow = makeWorkflow(
            projection: ProjectionInteractionSpy(definition: nil),
            materialization: materialization
        )

        workflow.cancelMaterialization()

        #expect(materialization.cancelCount == 1)
    }

    private func routeProjectionReloads(
        through workflow: HomeProjectionInteractionWorkflow,
        account: NostrAccount,
        probe: ProjectionReloadProbe
    ) {
        workflow.reloadNewestProjection(account: account) { probe.results.append($0) }
        workflow.reloadProjection(
            account: account,
            around: "anchor",
            mergingWithCurrentWindow: true
        ) { probe.results.append($0) }
    }

    private func makeWorkflow(
        projection: ProjectionInteractionSpy,
        viewportStateRestorer: ViewportStateRestorerSpy =
            ViewportStateRestorerSpy(),
        materialization: MaterializationInteractionSpy =
            MaterializationInteractionSpy(),
        timestamp: Int = 100
    ) -> HomeProjectionInteractionWorkflow {
        HomeProjectionInteractionWorkflow(
            projection: projection,
            viewportStateRestorer: viewportStateRestorer,
            materialization: materialization,
            timestamp: { timestamp }
        )
    }

    private func account(character: Character) -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: String(character), count: 64),
            displayIdentifier: "projection",
            readOnly: true
        )
    }

    private func definition(accountID: String) -> NostrFeedDefinitionRecord {
        NostrFeedDefinitionRecord(
            feedID: HomeFeedProjectionBuilder.feedID(accountID: accountID),
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(),
            specificationHash: "projection-interaction",
            revision: 1,
            createdAt: 1, updatedAt: 1
        )
    }

    private func viewport(accountID: String) -> TimelineViewportState {
        TimelineViewportState(
            accountID: accountID,
            timelineKey: "home",
            anchorPostID: "anchor",
            anchorOffset: 12, contentOffset: 120,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func event(accountID: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: "1", count: 64), pubkey: accountID,
            createdAt: 100, kind: 1,
            tags: [], content: "note",
            sig: String(repeating: "0", count: 128)
        )
    }

}

@MainActor
private final class ProjectionInteractionSpy: HomeFeedProjectionControlling {
    let retainedWindowLimit = 320
    var definition: NostrFeedDefinitionRecord?
    private let isCurrentResult: Bool
    private(set) var prewarmedAccountID: String?
    private(set) var prewarmedFollowedPubkeys: [String] = []
    private(set) var prewarmedLiveEventIDs: [String] = []
    private(set) var prewarmedAt: Int?
    private(set) var currentContext: HomeFeedRuntimeContext?
    private(set) var currentAccountID: String?
    private(set) var activatedDefinition: NostrFeedDefinitionRecord?
    private(set) var activatedSourceAuthors: [String] = []

    init(
        definition: NostrFeedDefinitionRecord?,
        isCurrentResult: Bool = false
    ) {
        self.definition = definition
        self.isCurrentResult = isCurrentResult
    }

    func prewarmDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        now: Int
    ) {
        prewarmedAccountID = accountID
        prewarmedFollowedPubkeys = followedPubkeys
        prewarmedLiveEventIDs = liveEvents.map(\.id)
        prewarmedAt = now
    }

    func feedID(accountID: String) -> String? {
        guard definition?.accountID == accountID || prewarmedAccountID == accountID else {
            return nil
        }
        return HomeFeedProjectionBuilder.feedID(accountID: accountID)
    }

    func isCurrent(
        _ context: HomeFeedRuntimeContext?,
        accountID: String?
    ) -> Bool {
        currentContext = context
        currentAccountID = accountID
        return isCurrentResult
    }
    func activateStoredProjection(
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    ) async {
        activatedDefinition = definition
        activatedSourceAuthors = sourceAuthors
    }
}

@MainActor
private final class ViewportStateRestorerSpy:
    HomeTimelineViewportStateRestoring {
    private let result: TimelineViewportState?

    private(set) var accountID: String?
    private(set) var timelineKey: String?
    private(set) var callCount = 0

    init(result: TimelineViewportState? = nil) {
        self.result = result
    }

    func viewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        self.accountID = accountID
        self.timelineKey = timelineKey
        callCount += 1
        return result
    }
}

@MainActor
private final class MaterializationInteractionSpy:
    HomeTimelineMaterializationCoordinating {
    private let reloadNewestResult: Bool
    private let reloadResult: Bool
    private(set) var newestAccountID: String?
    private(set) var reloadAccountID: String?
    private(set) var reloadAnchorEventID: String?
    private(set) var reloadMergesCurrentWindow = false
    private(set) var materializationAccountID: String?
    private(set) var allowsRealtimeFollow = false
    private(set) var cancelCount = 0

    init(
        reloadNewestResult: Bool = false,
        reloadResult: Bool = false
    ) {
        self.reloadNewestResult = reloadNewestResult
        self.reloadResult = reloadResult
    }

    func reloadNewestProjection(
        account: NostrAccount, onCompletion: ProjectionReloadHandler?
    ) {
        newestAccountID = account.pubkey
        onCompletion?(reloadNewestResult)
    }

    func reloadProjection(
        account: NostrAccount, around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: ProjectionReloadHandler?
    ) {
        reloadAccountID = account.pubkey
        reloadAnchorEventID = anchorEventID
        reloadMergesCurrentWindow = mergingWithCurrentWindow
        onCompletion?(reloadResult)
    }

    func materialize(
        _ request: HomeTimelineMaterializationRequest,
        onTransition: @escaping TransitionHandler
    ) {
        materializationAccountID = request.account?.pubkey
        allowsRealtimeFollow = request.allowsRealtimeFollow
    }
    func waitForPendingPresentation() async {}
    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class ProjectionReloadProbe { var results: [Bool] = [] }
