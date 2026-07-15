import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline projection interaction workflow")
@MainActor
struct HomeProjectionInteractionWorkflowTests {
    @Test("Active feed identity gates viewport and read state operations")
    func activeFeedIdentityGatesReadState() throws {
        let account = account(character: "a")
        let definition = definition(accountID: account.pubkey)
        let projection = ProjectionInteractionSpy(definition: definition)
        let readState = ReadStateInteractionSpy(
            restoredReadBoundaryResult: "boundary"
        )
        let workflow = makeWorkflow(
            projection: projection,
            readState: readState,
            timestamp: 321
        )
        let positions = [
            HomeTimelineReadPosition(postID: "boundary", createdAt: 100)
        ]
        let boundary = NostrTimelineEntryCursor(
            sortTimestamp: 100,
            eventID: "boundary"
        )

        #expect(workflow.scheduleViewportState(viewport(accountID: account.pubkey)))
        #expect(workflow.restoredReadBoundaryPostID(
            accountID: account.pubkey,
            positions: positions
        ) == "boundary")
        #expect(workflow.scheduleReadBoundarySave(
            accountID: account.pubkey,
            boundary: boundary
        ))

        _ = try #require(readState.viewportWriteState)
        #expect(readState.viewportWriteFeedID == definition.feedID)
        #expect(readState.viewportWriteScopeID == account.pubkey)
        #expect(readState.restoredBoundaryFeedID == definition.feedID)
        #expect(readState.restoredBoundaryPositions == positions)
        let boundaryWrite = try #require(readState.readBoundaryWrite)
        #expect(boundaryWrite.scopeID == account.pubkey)
        #expect(boundaryWrite.feedID == definition.feedID)
        #expect(boundaryWrite.boundary == boundary)
        #expect(boundaryWrite.updatedAt == 321)

        #expect(!workflow.scheduleViewportState(
            viewport(accountID: String(repeating: "b", count: 64))
        ))
        #expect(workflow.restoredReadBoundaryPostID(
            accountID: String(repeating: "b", count: 64),
            positions: positions
        ) == nil)
        #expect(readState.viewportWriteCount == 1)
        #expect(readState.restoredBoundaryCallCount == 1)
    }

    @Test("Startup viewport restoration does not require an activated projection")
    func startupViewportRestorationPrecedesProjectionActivation() {
        let account = account(character: "a")
        let restored = viewport(accountID: account.pubkey)
        let readState = ReadStateInteractionSpy(
            restoredViewportResult: restored
        )
        let workflow = makeWorkflow(
            projection: ProjectionInteractionSpy(definition: nil),
            readState: readState
        )

        #expect(workflow.restoredViewportState(
            accountID: account.pubkey,
            timelineKey: "home"
        ) == restored)
        #expect(!workflow.scheduleViewportState(restored))
        #expect(workflow.readBoundaryWrite(
            accountID: account.pubkey,
            boundary: nil
        ) == nil)
        #expect(readState.restoredViewportAccountID == account.pubkey)
        #expect(readState.restoredViewportTimelineKey == "home")
        #expect(readState.viewportWriteCount == 0)
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
        let request = HomeTimelineMaterializationRequest(
            account: account,
            nip05Resolutions: [:],
            profileResolutionStates: [:],
            policy: .default(networkType: .unknown, lowPowerMode: false),
            allowsRealtimeFollow: true
        )

        workflow.ensureDefinition(
            account: account,
            followedPubkeys: [account.pubkey],
            liveEvents: [liveEvent]
        )
        #expect(workflow.isCurrent(context, accountID: account.pubkey))
        #expect(workflow.reloadNewestProjection(account: account))
        #expect(workflow.reloadProjection(
            account: account,
            around: "anchor",
            mergingWithCurrentWindow: true
        ))
        #expect(workflow.materialize(request) == nil)

        #expect(projection.ensuredAccountID == account.pubkey)
        #expect(projection.ensuredFollowedPubkeys == [account.pubkey])
        #expect(projection.ensuredLiveEventIDs == [liveEvent.id])
        #expect(projection.ensuredAt == 654)
        #expect(projection.currentContext == context)
        #expect(projection.currentAccountID == account.pubkey)
        #expect(materialization.newestAccountID == account.pubkey)
        #expect(materialization.reloadAccountID == account.pubkey)
        #expect(materialization.reloadAnchorEventID == "anchor")
        #expect(materialization.reloadMergesCurrentWindow)
        #expect(materialization.materializationAccountID == account.pubkey)
        #expect(materialization.allowsRealtimeFollow)
    }

    private func makeWorkflow(
        projection: ProjectionInteractionSpy,
        readState: ReadStateInteractionSpy = ReadStateInteractionSpy(),
        materialization: MaterializationInteractionSpy =
            MaterializationInteractionSpy(),
        timestamp: Int = 100
    ) -> HomeProjectionInteractionWorkflow {
        HomeProjectionInteractionWorkflow(
            projection: projection,
            readState: readState,
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
            createdAt: 1,
            updatedAt: 1
        )
    }

    private func viewport(accountID: String) -> TimelineViewportState {
        TimelineViewportState(
            accountID: accountID,
            timelineKey: "home",
            anchorPostID: "anchor",
            anchorOffset: 12,
            contentOffset: 120,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func event(accountID: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: accountID,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "note",
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
private final class ProjectionInteractionSpy: HomeFeedProjectionControlling {
    let retainedWindowLimit = 320
    var definition: NostrFeedDefinitionRecord?
    private let isCurrentResult: Bool
    private(set) var ensuredAccountID: String?
    private(set) var ensuredFollowedPubkeys: [String] = []
    private(set) var ensuredLiveEventIDs: [String] = []
    private(set) var ensuredAt: Int?
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

    func ensureDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        now: Int
    ) {
        ensuredAccountID = accountID
        ensuredFollowedPubkeys = followedPubkeys
        ensuredLiveEventIDs = liveEvents.map(\.id)
        ensuredAt = now
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
    ) {
        activatedDefinition = definition
        activatedSourceAuthors = sourceAuthors
    }
}

@MainActor
private final class ReadStateInteractionSpy: HomeTimelineReadStateCoordinating {
    private let restoredViewportResult: TimelineViewportState?
    private let restoredReadBoundaryResult: String?
    private(set) var restoredViewportAccountID: String?
    private(set) var restoredViewportTimelineKey: String?
    private(set) var restoredBoundaryFeedID: String?
    private(set) var restoredBoundaryPositions: [HomeTimelineReadPosition] = []
    private(set) var restoredBoundaryCallCount = 0
    private(set) var viewportWriteState: TimelineViewportState?
    private(set) var viewportWriteFeedID: String?
    private(set) var viewportWriteScopeID: String?
    private(set) var viewportWriteCount = 0
    private(set) var readBoundaryWrite: HomeTimelineReadBoundaryWrite?
    private(set) var flushCount = 0

    init(
        restoredViewportResult: TimelineViewportState? = nil,
        restoredReadBoundaryResult: String? = nil
    ) {
        self.restoredViewportResult = restoredViewportResult
        self.restoredReadBoundaryResult = restoredReadBoundaryResult
    }

    func restoredViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        restoredViewportAccountID = accountID
        restoredViewportTimelineKey = timelineKey
        return restoredViewportResult
    }

    func restoredReadBoundaryPostID(
        feedID: String,
        positions: [HomeTimelineReadPosition]
    ) -> String? {
        restoredBoundaryFeedID = feedID
        restoredBoundaryPositions = positions
        restoredBoundaryCallCount += 1
        return restoredReadBoundaryResult
    }

    func scheduleViewportState(
        _ state: TimelineViewportState,
        feedID: String,
        scopeID: String
    ) -> Bool {
        viewportWriteState = state
        viewportWriteFeedID = feedID
        viewportWriteScopeID = scopeID
        viewportWriteCount += 1
        return true
    }

    func scheduleReadBoundarySave(
        _ write: HomeTimelineReadBoundaryWrite
    ) -> Bool {
        readBoundaryWrite = write
        return true
    }

    func flushPendingViewportWrite() {
        flushCount += 1
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

    init(
        reloadNewestResult: Bool = false,
        reloadResult: Bool = false
    ) {
        self.reloadNewestResult = reloadNewestResult
        self.reloadResult = reloadResult
    }

    func reloadNewestProjection(account: NostrAccount) -> Bool {
        newestAccountID = account.pubkey
        return reloadNewestResult
    }

    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool
    ) -> Bool {
        reloadAccountID = account.pubkey
        reloadAnchorEventID = anchorEventID
        reloadMergesCurrentWindow = mergingWithCurrentWindow
        return reloadResult
    }

    func materialize(
        _ request: HomeTimelineMaterializationRequest
    ) -> HomeTimelinePresentationTransition? {
        materializationAccountID = request.account?.pubkey
        allowsRealtimeFollow = request.allowsRealtimeFollow
        return nil
    }
}
