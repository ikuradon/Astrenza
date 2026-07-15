import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline runtime event application coordinator")
@MainActor
struct HomeTimelineRuntimeEventApplicationCoordinatorTests {
    @Test("Forward notes invalidate list state and preserve realtime projection commands")
    func forwardNoteApplication() async {
        let fixture = makeFixture()
        let note = event(idCharacter: "1", pubkey: fixture.account.pubkey, kind: 1)
        var plan = HomeTimelineRuntimeEventApplicationPlan()
        plan.invalidatesListEntries = true
        plan.dependencyEvent = note
        plan.projectionUpdate = .reloadNewestAndSchedule(allowsRealtimeFollow: true)

        let applied = await fixture.coordinator.apply(
            plan,
            backwardRequestKey: nil,
            context: fixture.context,
            handlers: handlers(probe: fixture.probe)
        )

        #expect(applied)
        #expect(fixture.probe.listRevisions == [1])
        #expect(fixture.probe.commands == [
            .requestNewestProjectionReloadAndSchedule(allowsRealtimeFollow: true)
        ])
        #expect(!fixture.pendingBuffer.hasEvents)
    }

    @Test("Metadata resolution updates content and requests a second materialization")
    func metadataResolutionApplication() async {
        let account = account()
        let identifier = "alice@example.com"
        let resolution = NostrNIP05Resolution(
            identifier: identifier,
            pubkey: account.pubkey,
            relays: ["wss://relay.example"],
            status: .verified,
            resolvedAt: Date(timeIntervalSince1970: 100)
        )
        let fixture = makeFixture(
            fixtureAccount: account,
            resolver: StubRuntimeApplicationNIP05Resolver(resolution: resolution)
        )
        let metadata = event(
            idCharacter: "2",
            pubkey: account.pubkey,
            kind: 0,
            content: #"{"name":"Alice","nip05":"alice@example.com"}"#
        )
        var plan = HomeTimelineRuntimeEventApplicationPlan()
        plan.metadataEvent = metadata
        plan.materializationSchedule = .standard

        let applied = await fixture.coordinator.apply(
            plan,
            backwardRequestKey: nil,
            context: fixture.context,
            handlers: handlers(probe: fixture.probe)
        )
        for _ in 0..<100 where fixture.probe.persistedAccountIDs.isEmpty {
            await Task.yield()
        }

        #expect(applied)
        #expect(fixture.content.metadataEvents == [metadata])
        #expect(fixture.dependency.nip05Resolutions[account.pubkey] == resolution)
        #expect(fixture.probe.listRevisions == [1, 2])
        #expect(fixture.probe.commands == [
            .scheduleMaterialization(.standard),
            .scheduleMaterialization(.standard)
        ])
        #expect(fixture.probe.persistedAccountIDs == [account.pubkey])
    }

    @Test("Deletion removes projected content before requesting an immediate reload")
    func deletionApplication() async {
        let fixture = makeFixture()
        let target = event(idCharacter: "3", pubkey: fixture.account.pubkey, kind: 1)
        let retained = event(idCharacter: "4", pubkey: fixture.account.pubkey, kind: 1)
        installContent([target, retained], in: fixture)
        let deletion = event(
            idCharacter: "5",
            pubkey: fixture.account.pubkey,
            kind: 5,
            tags: [["e", target.id]]
        )
        var plan = HomeTimelineRuntimeEventApplicationPlan()
        plan.invalidatesListEntries = true
        plan.deletion = .init(event: deletion, materialization: .immediate)

        let applied = await fixture.coordinator.apply(
            plan,
            backwardRequestKey: nil,
            context: fixture.context,
            handlers: handlers(probe: fixture.probe)
        )

        #expect(applied)
        #expect(fixture.content.noteEvents.map(\.id) == [retained.id])
        #expect(fixture.probe.listRevisions == [1])
        #expect(fixture.probe.commands == [
            .reloadProjection(anchorEventID: target.id, materialization: .immediate)
        ])
    }

    @Test("Detached notes update backward progress and the pending buffer without following")
    func pendingNoteApplication() async throws {
        let fixture = makeFixture()
        let context = try feedContext(accountID: fixture.account.pubkey)
        fixture.registry.registerOlderPage(
            groupID: "older-group",
            context: context,
            anchorEventID: nil
        )
        let note = event(idCharacter: "6", pubkey: fixture.account.pubkey, kind: 1)
        var plan = HomeTimelineRuntimeEventApplicationPlan()
        plan.backwardTimelineEventID = note.id
        plan.projectionUpdate = .bufferPendingEvent(note.id)

        let applied = await fixture.coordinator.apply(
            plan,
            backwardRequestKey: "older-group",
            context: fixture.context,
            handlers: handlers(probe: fixture.probe)
        )
        for _ in 0..<100 where fixture.probe.pendingCounts.isEmpty {
            await Task.yield()
        }

        #expect(applied)
        #expect(fixture.registry.request(for: "older-group")?.receivedTimelineEventIDs == [note.id])
        #expect(fixture.pendingBuffer.hasEvents)
        #expect(fixture.probe.pendingCounts == [1])
        #expect(fixture.probe.commands.isEmpty)
    }

    @Test("Stale lifecycle plans cannot mutate runtime state")
    func staleLifecycleApplication() async {
        let fixture = makeFixture()
        _ = fixture.lifecycle.cancel()
        var plan = HomeTimelineRuntimeEventApplicationPlan()
        plan.invalidatesListEntries = true
        plan.projectionUpdate = .bufferPendingEvent("stale")

        let applied = await fixture.coordinator.apply(
            plan,
            backwardRequestKey: nil,
            context: fixture.context,
            handlers: handlers(probe: fixture.probe)
        )

        #expect(!applied)
        #expect(fixture.probe.listRevisions.isEmpty)
        #expect(fixture.probe.pendingCounts.isEmpty)
        #expect(fixture.probe.commands.isEmpty)
        #expect(!fixture.pendingBuffer.hasEvents)
    }

    private func makeFixture(
        fixtureAccount: NostrAccount? = nil,
        resolver: any NostrNIP05Resolving = StubRuntimeApplicationNIP05Resolver()
    ) -> Fixture {
        let account = fixtureAccount ?? account()
        let content = HomeTimelineContentCoordinator(eventStore: nil)
        let dependency = HomeTimelineDependencyResolutionCoordinator(
            eventIngestor: HomeTimelineEventIngestor(eventStore: nil),
            profileDirectory: nil,
            nip05Resolver: resolver,
            syncPlanner: HomeTimelineSyncPlanner()
        )
        let listProjectionCache = HomeTimelineListProjectionCache()
        let pendingBuffer = HomeTimelinePendingEventBuffer(
            countPublishDelayNanoseconds: 0,
            delay: { _ in }
        )
        let registry = HomeTimelineBackwardRequestRegistry()
        let lifecycle = HomeTimelineLifecycleCoordinator()
        let token = lifecycle.begin(accountID: account.pubkey)
        let coordinator = HomeTimelineRuntimeEventApplicationCoordinator(
            contentCoordinator: content,
            dependencyCoordinator: dependency,
            listProjectionCache: listProjectionCache,
            pendingEventBuffer: pendingBuffer,
            backwardRequestRegistry: registry,
            lifecycleCoordinator: lifecycle
        )
        return Fixture(
            coordinator: coordinator,
            content: content,
            dependency: dependency,
            pendingBuffer: pendingBuffer,
            registry: registry,
            lifecycle: lifecycle,
            account: account,
            context: HomeTimelineRuntimeEventApplicationContext(
                account: account,
                lifecycle: token,
                hasRelayRuntime: false
            ),
            probe: RuntimeEventApplicationProbe()
        )
    }

    private func handlers(
        probe: RuntimeEventApplicationProbe
    ) -> HomeTimelineRuntimeEventApplicationHandlers {
        HomeTimelineRuntimeEventApplicationHandlers(
            applyListProjectionInvalidation: { invalidation in
                probe.listRevisions.append(invalidation.revision)
            },
            pendingCountChanged: { count in
                probe.pendingCounts.append(count)
            },
            perform: { command in
                probe.commands.append(command)
            },
            persistTimelineMetadata: { account in
                probe.persistedAccountIDs.append(account.pubkey)
            },
            sourceInstallFailed: { message in
                probe.sourceInstallFailures.append(message)
            }
        )
    }

    private func installContent(
        _ events: [NostrEvent],
        in fixture: Fixture
    ) {
        _ = fixture.content.replace(
            with: NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [fixture.account.pubkey],
                noteEvents: events,
                metadataEvents: []
            ),
            accountID: fixture.account.pubkey
        )
    }

    private func feedContext(accountID: String) throws -> HomeFeedRuntimeContext {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [accountID], kinds: [1, 6])
        )
        return HomeFeedRuntimeContext(definition: NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: specification,
            specificationHash: "specification",
            revision: 1,
            createdAt: 1,
            updatedAt: 1
        ))
    }

    private func account() -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
    }

    private func event(
        idCharacter: String,
        pubkey: String,
        kind: Int,
        tags: [[String]] = [],
        content: String = "event"
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: idCharacter, count: 64),
            pubkey: pubkey,
            createdAt: 100,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "0", count: 128)
        )
    }

    private struct Fixture {
        let coordinator: HomeTimelineRuntimeEventApplicationCoordinator
        let content: HomeTimelineContentCoordinator
        let dependency: HomeTimelineDependencyResolutionCoordinator
        let pendingBuffer: HomeTimelinePendingEventBuffer
        let registry: HomeTimelineBackwardRequestRegistry
        let lifecycle: HomeTimelineLifecycleCoordinator
        let account: NostrAccount
        let context: HomeTimelineRuntimeEventApplicationContext
        let probe: RuntimeEventApplicationProbe
    }
}

@MainActor
private final class RuntimeEventApplicationProbe {
    var listRevisions: [Int] = []
    var pendingCounts: [Int] = []
    var commands: [HomeTimelineRuntimeEventApplicationCommand] = []
    var persistedAccountIDs: [String] = []
    var sourceInstallFailures: [String] = []
}

private struct StubRuntimeApplicationNIP05Resolver: NostrNIP05Resolving {
    let resolution: NostrNIP05Resolution

    init(
        resolution: NostrNIP05Resolution = NostrNIP05Resolution(
            identifier: "",
            pubkey: nil,
            relays: [],
            status: .absent
        )
    ) {
        self.resolution = resolution
    }

    func resolve(identifier: String, expectedPubkey: String?) async -> NostrNIP05Resolution {
        resolution
    }
}
