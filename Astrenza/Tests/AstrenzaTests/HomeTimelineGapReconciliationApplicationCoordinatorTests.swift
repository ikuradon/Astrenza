import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline gap reconciliation application coordinator")
struct HomeTimelineGapReconciliationApplicationCoordinatorTests {
    @Test("A current gap applies diagnostics, dependencies, reload, and activity lifecycle")
    @MainActor
    func appliesCurrentGapExecution() async throws {
        let recoveredEvent = gapEvent(idCharacter: "3", createdAt: 150)
        let diagnostic = HomeTimelineGapReconciliationDiagnostic(
            relayURL: "wss://failed.example",
            subscriptionID: "astrenza-neg-gap",
            message: "verification failed"
        )
        let system = try GapReconciliationApplicationTestSystem(
            execution: HomeTimelineGapReconciliationExecution(
                recoveredEvents: [recoveredEvent],
                diagnostics: [diagnostic],
                reloadsProjection: true
            )
        )

        #expect(system.application.start(
            system.gap,
            feedContext: system.requestContext,
            account: system.account,
            handlers: system.handlers
        ))
        await system.application.waitUntilIdle()

        #expect(system.probe.commands == [
            .incrementRelayStatusRevision,
            .recordDiagnostic(diagnostic),
            .reloadProjection(anchorEventID: system.gap.newerPostID),
            .incrementRelayStatusRevision
        ])
        #expect(system.probe.dependencyEvents == [recoveredEvent])
        #expect(system.registry.activeGapReconciliationCount == 0)
        #expect(system.application.activeTaskCount == 0)

        let call = try #require(await system.executor.receivedCalls().first)
        #expect(call.newerEvent == system.newerEvent)
        #expect(call.olderEvent == system.olderEvent)
        #expect(call.gap == system.gap)
        #expect(call.context == system.requestContext)
        #expect(call.relays == [system.relayURL])
        #expect(call.inMemoryEvents == [system.newerEvent, system.olderEvent])
    }

    @Test("A missing boundary finishes activity without invoking reconciliation")
    @MainActor
    func finishesWhenBoundaryIsMissing() async throws {
        let system = try GapReconciliationApplicationTestSystem(
            execution: .empty,
            includesOlderBoundary: false
        )

        #expect(system.application.start(
            system.gap,
            feedContext: system.requestContext,
            account: system.account,
            handlers: system.handlers
        ))
        await system.application.waitUntilIdle()

        #expect(await system.executor.receivedCalls().isEmpty)
        #expect(system.probe.commands == [
            .incrementRelayStatusRevision,
            .incrementRelayStatusRevision
        ])
        #expect(system.registry.activeGapReconciliationCount == 0)
    }

    @Test("A stale feed is rejected before registering reconciliation activity")
    @MainActor
    func rejectsStaleFeed() async throws {
        let system = try GapReconciliationApplicationTestSystem(
            execution: .empty,
            activeRevision: 2,
            requestRevision: 1
        )

        #expect(!system.application.start(
            system.gap,
            feedContext: system.requestContext,
            account: system.account,
            handlers: system.handlers
        ))

        #expect(await system.executor.receivedCalls().isEmpty)
        #expect(system.probe.commands.isEmpty)
        #expect(system.registry.activeGapReconciliationCount == 0)
        #expect(system.application.activeTaskCount == 0)
    }

    @Test("A feed superseded during reconciliation discards output but finishes activity")
    @MainActor
    func discardsSupersededFeedOutput() async throws {
        let recoveredEvent = gapEvent(idCharacter: "4", createdAt: 150)
        let diagnostic = HomeTimelineGapReconciliationDiagnostic(
            relayURL: "wss://relay.example",
            subscriptionID: "astrenza-neg-gap",
            message: "late result"
        )
        let system = try GapReconciliationApplicationTestSystem(
            execution: HomeTimelineGapReconciliationExecution(
                recoveredEvents: [recoveredEvent],
                diagnostics: [diagnostic],
                reloadsProjection: true
            ),
            supersedesFeedBeforeReturning: true
        )

        #expect(system.application.start(
            system.gap,
            feedContext: system.requestContext,
            account: system.account,
            handlers: system.handlers
        ))
        await system.application.waitUntilIdle()

        #expect(system.probe.commands == [
            .incrementRelayStatusRevision,
            .incrementRelayStatusRevision
        ])
        #expect(system.probe.dependencyEvents.isEmpty)
        #expect(system.registry.activeGapReconciliationCount == 0)
    }

    @Test("Duplicate starts are coalesced into one reconciliation task")
    @MainActor
    func coalescesDuplicateStarts() async throws {
        let system = try GapReconciliationApplicationTestSystem(execution: .empty)

        #expect(system.application.start(
            system.gap,
            feedContext: system.requestContext,
            account: system.account,
            handlers: system.handlers
        ))
        #expect(!system.application.start(
            system.gap,
            feedContext: system.requestContext,
            account: system.account,
            handlers: system.handlers
        ))
        await system.application.waitUntilIdle()

        #expect(await system.executor.receivedCalls().count == 1)
        #expect(system.probe.commands == [
            .incrementRelayStatusRevision,
            .incrementRelayStatusRevision
        ])
        #expect(system.registry.activeGapReconciliationCount == 0)
    }

    @Test("Cancellation releases the active gap and suppresses stale completion commands")
    @MainActor
    func cancellationReleasesActiveGap() async throws {
        let system = try GapReconciliationApplicationTestSystem(
            execution: HomeTimelineGapReconciliationExecution(
                recoveredEvents: [],
                diagnostics: [HomeTimelineGapReconciliationDiagnostic(
                    relayURL: "wss://relay.example",
                    subscriptionID: nil,
                    message: "must not escape cancellation"
                )],
                reloadsProjection: true
            )
        )

        #expect(system.application.start(
            system.gap,
            feedContext: system.requestContext,
            account: system.account,
            handlers: system.handlers
        ))
        system.application.cancel()
        await Task.yield()

        #expect(system.probe.commands == [.incrementRelayStatusRevision])
        #expect(system.registry.activeGapReconciliationCount == 0)
        #expect(system.application.activeTaskCount == 0)
    }

    private func gapEvent(
        idCharacter: Character,
        createdAt: Int
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(idCharacter), count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: String(idCharacter),
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
private struct GapReconciliationApplicationTestSystem {
    let relayURL = "wss://relay.example"
    let account: NostrAccount
    let activeDefinition: NostrFeedDefinitionRecord
    let requestContext: HomeFeedRuntimeContext
    let newerEvent: NostrEvent
    let olderEvent: NostrEvent
    let gap: PendingGapBackfill
    let registry: HomeTimelineBackwardRequestRegistry
    let executor: GapReconciliationApplicationExecutorStub
    let application: HomeTimelineGapReconciliationApplicationCoordinator
    let probe: GapReconciliationApplicationProbe

    var handlers: HomeTimelineGapReconciliationApplicationHandlers {
        HomeTimelineGapReconciliationApplicationHandlers(
            perform: { [probe] command in
                probe.commands.append(command)
            },
            resolveDependencies: { [probe] event, _ in
                probe.dependencyEvents.append(event)
                return probe.resolvesDependencies
            }
        )
    }

    init(
        execution: HomeTimelineGapReconciliationExecution,
        includesOlderBoundary: Bool = true,
        activeRevision: Int = 1,
        requestRevision: Int? = nil,
        supersedesFeedBeforeReturning: Bool = false
    ) throws {
        let accountID = String(repeating: "a", count: 64)
        let account = NostrAccount(
            pubkey: accountID,
            displayIdentifier: "account",
            readOnly: true
        )
        let activeDefinition = try Self.definition(
            accountID: accountID,
            revision: activeRevision
        )
        let requestDefinition = try Self.definition(
            accountID: accountID,
            revision: requestRevision ?? activeRevision
        )
        let supersedingDefinition = try Self.definition(
            accountID: accountID,
            revision: activeRevision + 1
        )
        let newerEvent = Self.event(
            idCharacter: "1",
            pubkey: accountID,
            createdAt: 200
        )
        let olderEvent = Self.event(
            idCharacter: "2",
            pubkey: accountID,
            createdAt: 100
        )
        let gap = PendingGapBackfill(
            newerPostID: newerEvent.id,
            olderPostID: olderEvent.id,
            direction: .older
        )
        let content = HomeTimelineContentCoordinator(eventStore: nil)
        _ = content.replace(
            with: NostrHomeTimelineState(
                relays: [relayURL],
                followedPubkeys: [accountID],
                noteEvents: includesOlderBoundary
                    ? [newerEvent, olderEvent]
                    : [newerEvent],
                metadataEvents: []
            ),
            accountID: accountID
        )
        let projection = HomeFeedProjectionController(eventStore: nil)
        projection.activate(
            definition: activeDefinition,
            window: nil,
            sourceAuthors: [accountID]
        )
        let lifecycle = HomeTimelineLifecycleCoordinator()
        lifecycle.begin(accountID: accountID)
        let registry = HomeTimelineBackwardRequestRegistry()
        let beforeReturning: (@MainActor @Sendable () -> Void)?
        if supersedesFeedBeforeReturning {
            beforeReturning = {
                projection.activate(
                    definition: supersedingDefinition,
                    window: nil,
                    sourceAuthors: [accountID]
                )
            }
        } else {
            beforeReturning = nil
        }
        let executor = GapReconciliationApplicationExecutorStub(
            execution: execution,
            beforeReturning: beforeReturning
        )
        let probe = GapReconciliationApplicationProbe()

        self.account = account
        self.activeDefinition = activeDefinition
        self.requestContext = HomeFeedRuntimeContext(definition: requestDefinition)
        self.newerEvent = newerEvent
        self.olderEvent = olderEvent
        self.gap = gap
        self.registry = registry
        self.executor = executor
        self.probe = probe
        self.application = HomeTimelineGapReconciliationApplicationCoordinator(
            reconciliationCoordinator: executor,
            contentCoordinator: content,
            timelineRepository: HomeTimelineRepository(eventStore: nil),
            projectionController: projection,
            backwardRequestRegistry: registry,
            lifecycleCoordinator: lifecycle
        )
    }

    private static func definition(
        accountID: String,
        revision: Int
    ) throws -> NostrFeedDefinitionRecord {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [accountID], kinds: [1, 6])
        )
        return NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: specification,
            specificationHash: "specification-\(revision)",
            revision: revision,
            createdAt: 1,
            updatedAt: revision
        )
    }

    private static func event(
        idCharacter: Character,
        pubkey: String,
        createdAt: Int
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(idCharacter), count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: String(idCharacter),
            sig: String(repeating: "0", count: 128)
        )
    }
}

private actor GapReconciliationApplicationExecutorStub:
    HomeTimelineGapReconciliationExecuting {
    struct Call: Equatable, Sendable {
        let newerEvent: NostrEvent
        let olderEvent: NostrEvent
        let gap: PendingGapBackfill
        let context: HomeFeedRuntimeContext
        let relays: [String]
        let inMemoryEvents: [NostrEvent]
    }

    private let execution: HomeTimelineGapReconciliationExecution
    private let beforeReturning: (@MainActor @Sendable () -> Void)?
    private var calls: [Call] = []

    init(
        execution: HomeTimelineGapReconciliationExecution,
        beforeReturning: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.execution = execution
        self.beforeReturning = beforeReturning
    }

    func reconcile(
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext,
        relays: [String],
        inMemoryEvents: [NostrEvent]
    ) async -> HomeTimelineGapReconciliationExecution {
        calls.append(Call(
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            gap: gap,
            context: context,
            relays: relays,
            inMemoryEvents: inMemoryEvents
        ))
        if let beforeReturning {
            await beforeReturning()
        }
        return execution
    }

    func receivedCalls() -> [Call] {
        calls
    }
}

@MainActor
private final class GapReconciliationApplicationProbe {
    var commands: [HomeTimelineGapReconciliationApplicationCommand] = []
    var dependencyEvents: [NostrEvent] = []
    var resolvesDependencies = true
}

private extension HomeTimelineGapReconciliationExecution {
    static let empty = HomeTimelineGapReconciliationExecution(
        recoveredEvents: [],
        diagnostics: [],
        reloadsProjection: false
    )
}
