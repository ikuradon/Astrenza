import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline backward request coordinator")
struct BackwardRequestCoordinatorTests {
    @Test("An older page request installs an author-merged packet and registers its anchor")
    @MainActor
    func installsOlderPageRequest() async throws {
        let installer = BackwardRequestPacketInstallerSpy()
        let system = try BackwardRequestTestSystem(installer: installer)

        let task = Task {
            await system.application.requestOlder(account: system.account)
        }
        let packet = try await installedPacket(from: installer)
        let request = try #require(system.registry.request(for: packet.groupID))
        system.registry.complete(completion(groupID: packet.groupID))
        let outcome = await task.value

        #expect(outcome == .completed(system.activeDefinition))
        let installation = try #require(installer.installations.first)
        let filter = try #require(packet.filters.first)
        #expect(installer.installations.count == 1)
        #expect(installation.mergeField == .authors)
        #expect(packet.strategy == .backward)
        #expect(packet.relayURLs == [system.relayURL])
        #expect(filter["authors"] == .strings([system.account.pubkey]))
        #expect(filter["until"] == .int(system.olderEvent.createdAt - 1))
        #expect(request.feedContext == system.activeContext)
        #expect(request.isOlderPage)
        #expect(request.olderAnchorPostID == system.olderEvent.id)
        #expect(request.gap == nil)
    }

    @Test("A gap request installs its bounded packet and registers the fill direction")
    @MainActor
    func installsGapRequest() async throws {
        let installer = BackwardRequestPacketInstallerSpy()
        let system = try BackwardRequestTestSystem(installer: installer)

        let task = Task {
            await system.application.requestGap(
                account: system.account,
                gap: system.gap,
                direction: .newer
            )
        }
        let packet = try await installedPacket(from: installer)
        let request = try #require(system.registry.request(for: packet.groupID))
        system.registry.complete(completion(groupID: packet.groupID))
        let outcome = await task.value

        #expect(outcome == .completed(system.activeDefinition))
        let installation = try #require(installer.installations.first)
        let filter = try #require(packet.filters.first)
        #expect(installation.mergeField == .authors)
        #expect(filter["since"] == .int(system.olderEvent.createdAt + 1))
        #expect(filter["until"] == .int(system.newerEvent.createdAt - 1))
        #expect(filter["limit"] == .int(system.gap.missingEstimate))
        #expect(request.feedContext == system.activeContext)
        #expect(request.gap == PendingGapBackfill(
            newerPostID: system.newerEvent.id,
            olderPostID: system.olderEvent.id,
            direction: .newer
        ))
        #expect(!request.isOlderPage)
        #expect(system.gapStatePersistence.events == [
            .requested(
                newerEventID: system.newerEvent.id,
                olderEventID: system.olderEvent.id,
                feedID: system.activeDefinition.feedID
            )
        ])
    }

    @Test("An active older page request rejects duplicate installation")
    @MainActor
    func rejectsDuplicateOlderPageRequest() async throws {
        let installer = BackwardRequestPacketInstallerSpy()
        let system = try BackwardRequestTestSystem(installer: installer)
        let first = Task {
            await system.application.requestOlder(account: system.account)
        }
        let packet = try await installedPacket(from: installer)

        let duplicate = await system.application.requestOlder(account: system.account)

        #expect(duplicate == .unavailable)
        #expect(installer.installations.count == 1)
        system.registry.complete(completion(groupID: packet.groupID))
        let firstOutcome = await first.value
        #expect(firstOutcome == .completed(system.activeDefinition))
    }

    @Test("An active gap request rejects the same boundary pair")
    @MainActor
    func rejectsDuplicateGapRequest() async throws {
        let installer = BackwardRequestPacketInstallerSpy()
        let system = try BackwardRequestTestSystem(installer: installer)
        let first = Task {
            await system.application.requestGap(
                account: system.account,
                gap: system.gap,
                direction: .older
            )
        }
        let packet = try await installedPacket(from: installer)

        let duplicate = await system.application.requestGap(
            account: system.account,
            gap: system.gap,
            direction: .newer
        )

        #expect(duplicate == .unavailable)
        #expect(installer.installations.count == 1)
        system.registry.complete(completion(groupID: packet.groupID))
        let firstOutcome = await first.value
        #expect(firstOutcome == .completed(system.activeDefinition))
    }

    @Test("Full outbox older loading hedges remaining candidates after an empty primary EOSE")
    @MainActor
    func hedgesRemainingFullOutboxCandidates() async throws {
        let installer = BackwardRequestPacketInstallerSpy()
        let system = try BackwardRequestTestSystem(
            installer: installer,
            includesOutboxRelay: true
        )
        let policy = NostrSyncPolicy(
            mode: .fullOutbox,
            networkType: .wifi,
            lowPowerMode: false,
            tapToLoadMedia: false,
            queueOGPPreviews: true,
            disableOGPOnCellular: false
        )

        let task = Task {
            await system.application.requestOlder(
                account: system.account,
                policy: policy
            )
        }
        let primary = try await installedPacket(from: installer, at: 0)
        #expect(primary.relayURLs == [system.outboxRelayURL])
        system.registry.complete(completion(groupID: primary.groupID))

        let hedge = try await installedPacket(from: installer, at: 1)
        #expect(hedge.relayURLs == [system.relayURL])
        #expect(hedge.groupID != primary.groupID)
        system.registry.complete(completion(groupID: hedge.groupID))

        #expect(await task.value == .completed(system.activeDefinition))
        #expect(installer.installations.count == 2)
    }

    @Test("An unavailable installer performs no projection or registry work")
    @MainActor
    func skipsWithoutInstaller() async throws {
        let system = try BackwardRequestTestSystem(installer: nil)

        let outcome = await system.application.requestOlder(account: system.account)

        #expect(outcome == .unavailable)
        #expect(system.registry.requestCount == 0)
    }

    @Test("A gap with a missing boundary is not registered or installed")
    @MainActor
    func skipsGapWithMissingBoundary() async throws {
        let installer = BackwardRequestPacketInstallerSpy()
        let system = try BackwardRequestTestSystem(
            installer: installer,
            includesOlderBoundary: false
        )

        let outcome = await system.application.requestGap(
            account: system.account,
            gap: system.gap,
            direction: .older
        )

        #expect(outcome == .unavailable)
        #expect(installer.installations.isEmpty)
        #expect(system.registry.requestCount == 0)
    }

    @Test(
        "An installation failure rolls back registration and identifies the request",
        arguments: BackwardRequestFailureScenario.allCases
    )
    @MainActor
    func rollsBackFailedInstallation(
        scenario: BackwardRequestFailureScenario
    ) async throws {
        let installer = BackwardRequestPacketInstallerSpy(error: .installationFailed)
        let system = try BackwardRequestTestSystem(installer: installer)

        let outcome: HomeTimelineBackwardRequestOutcome
        switch scenario {
        case .older:
            outcome = await system.application.requestOlder(account: system.account)
        case .gap:
            outcome = await system.application.requestGap(
                account: system.account,
                gap: system.gap,
                direction: .older
            )
        }

        let packet = try #require(installer.installations.first?.packets.first)
        guard case .failed(let diagnostic) = outcome else {
            Issue.record("Expected a failed outcome")
            return
        }
        #expect(diagnostic == HomeTimelineBackwardRequestDiagnostic(
            relayURL: system.relayURL,
            subscriptionID: packet.subscriptionID,
            message: "\(scenario.failurePrefix): installation failed"
        ))
        #expect(system.registry.requestCount == 0)
        if scenario == .gap {
            #expect(system.gapStatePersistence.events == [
                .requested(
                    newerEventID: system.newerEvent.id,
                    olderEventID: system.olderEvent.id,
                    feedID: system.activeDefinition.feedID
                ),
                .unresolved(
                    newerEventID: system.newerEvent.id,
                    olderEventID: system.olderEvent.id,
                    feedID: system.activeDefinition.feedID
                )
            ])
        }
    }

    @Test("A cancelled installation rolls back without reporting a failure")
    @MainActor
    func rollsBackCancelledInstallation() async throws {
        let installer = BackwardRequestPacketInstallerSpy(throwsCancellation: true)
        let system = try BackwardRequestTestSystem(installer: installer)

        let outcome = await system.application.requestOlder(account: system.account)

        #expect(outcome == .unavailable)
        #expect(installer.installations.count == 1)
        #expect(system.registry.requestCount == 0)
    }

    @Test("A feed superseded during installation rolls back registration and does not report success")
    @MainActor
    func rejectsSupersededFeedAfterInstallation() async throws {
        let installer = BackwardRequestPacketInstallerSpy()
        let system = try BackwardRequestTestSystem(installer: installer)
        let supersedingDefinition = try system.definition(revision: 2)
        let accountID = system.account.pubkey
        let projection = system.projection
        installer.beforeReturning = { [projection, supersedingDefinition, accountID] in
            projection.activate(
                definition: supersedingDefinition,
                window: nil,
                sourceAuthors: [accountID]
            )
        }

        let outcome = await system.application.requestGap(
            account: system.account,
            gap: system.gap,
            direction: .older
        )

        #expect(outcome == .unavailable)
        #expect(installer.installations.count == 1)
        #expect(system.registry.requestCount == 0)
        #expect(system.gapStatePersistence.events.last == .unresolved(
            newerEventID: system.newerEvent.id,
            olderEventID: system.olderEvent.id,
            feedID: system.activeDefinition.feedID
        ))
    }

    @MainActor
    private func installedPacket(
        from installer: BackwardRequestPacketInstallerSpy,
        at index: Int = 0
    ) async throws -> NostrREQPacket {
        for _ in 0..<40 where installer.installations.count <= index {
            await Task.yield()
        }
        guard installer.installations.indices.contains(index) else {
            Issue.record("Expected backward installation at index \(index)")
            throw CancellationError()
        }
        return try #require(installer.installations[index].packets.first)
    }

    private func completion(groupID: String) -> NostrBackwardREQCompletion {
        NostrBackwardREQCompletion(
            groupID: groupID,
            relayURLs: ["wss://relay.example"],
            subscriptionIDs: ["\(groupID)-relay"],
            eventCount: 0,
            eoseCount: 1,
            closedCount: 0,
            timeoutCount: 0
        )
    }
}

enum BackwardRequestFailureScenario: CaseIterable, Sendable {
    case older
    case gap

    var failurePrefix: String {
        switch self {
        case .older:
            "older enqueue failed"
        case .gap:
            "gap enqueue failed"
        }
    }
}

extension BackwardRequestFailureScenario: CustomTestStringConvertible {
    var testDescription: String {
        switch self {
        case .older:
            "older page"
        case .gap:
            "gap"
        }
    }
}

@MainActor
private struct BackwardRequestTestSystem {
    let relayURL = "wss://relay.example"
    let outboxRelayURL = "wss://outbox.example"
    let account: NostrAccount
    let newerEvent: NostrEvent
    let olderEvent: NostrEvent
    let gap: TimelineGap
    let activeDefinition: NostrFeedDefinitionRecord
    let activeContext: HomeFeedRuntimeContext
    let projection: HomeFeedProjectionController
    let registry: HomeTimelineBackwardRequestRegistry
    let gapStatePersistence: BackwardRequestGapStatePersistenceSpy
    let application: HomeTimelineBackwardRequestCoordinator

    init(
        installer: BackwardRequestPacketInstallerSpy?,
        includesOlderBoundary: Bool = true,
        includesOutboxRelay: Bool = false
    ) throws {
        let model = try Self.modelFixture()
        let content = Self.content(
            model: model,
            relayURL: relayURL,
            includesOlderBoundary: includesOlderBoundary,
            outboxRelayURL: includesOutboxRelay ? outboxRelayURL : nil
        )
        let projection = Self.projection(model: model)
        let registry = HomeTimelineBackwardRequestRegistry()
        let gapStatePersistence = BackwardRequestGapStatePersistenceSpy()

        self.account = model.account
        self.newerEvent = model.newerEvent
        self.olderEvent = model.olderEvent
        self.gap = model.gap
        self.activeDefinition = model.definition
        self.activeContext = HomeFeedRuntimeContext(definition: model.definition)
        self.projection = projection
        self.registry = registry
        self.gapStatePersistence = gapStatePersistence
        self.application = HomeTimelineBackwardRequestCoordinator(
            contentCoordinator: content,
            timelineRepository: HomeTimelineRepository(eventStore: nil),
            projectionController: projection,
            backwardRequestRegistry: registry,
            syncPlanner: HomeTimelineSyncPlanner(),
            packetInstaller: Self.packetInstaller(for: installer),
            gapStatePersistence: gapStatePersistence
        )
    }

    private struct ModelFixture {
        let account: NostrAccount
        let newerEvent: NostrEvent
        let olderEvent: NostrEvent
        let gap: TimelineGap
        let definition: NostrFeedDefinitionRecord
    }

    private static func modelFixture() throws -> ModelFixture {
        let accountID = String(repeating: "a", count: 64)
        let account = NostrAccount(
            pubkey: accountID, displayIdentifier: "account", readOnly: true
        )
        let newerEvent = Self.event(idCharacter: "1", pubkey: accountID, createdAt: 300)
        let olderEvent = Self.event(idCharacter: "2", pubkey: accountID, createdAt: 100)
        let gap = TimelineGap(
            id: "gap",
            newerPostID: newerEvent.id,
            olderPostID: olderEvent.id,
            missingEstimate: 8,
            relayCount: 1,
            state: .needsBackfill,
            backfilledPosts: []
        )
        let definition = try Self.definition(accountID: accountID, revision: 1)
        return ModelFixture(
            account: account,
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            gap: gap,
            definition: definition
        )
    }

    private static func content(
        model: ModelFixture,
        relayURL: String,
        includesOlderBoundary: Bool,
        outboxRelayURL: String?
    ) -> HomeTimelineContentCoordinator {
        let content = HomeTimelineContentCoordinator(eventStore: nil)
        let authorRelayListEvents = outboxRelayURL.map { relayURL in
            [NostrEvent(
                id: String(repeating: "3", count: 64),
                pubkey: model.account.pubkey,
                createdAt: 400,
                kind: 10_002,
                tags: [["r", relayURL, "write"]],
                content: "",
                sig: String(repeating: "0", count: 128)
            )]
        } ?? []
        _ = content.replace(
            with: NostrHomeTimelineState(
                relays: [relayURL],
                followedPubkeys: [model.account.pubkey],
                noteEvents: includesOlderBoundary
                    ? [model.newerEvent, model.olderEvent]
                    : [model.newerEvent],
                metadataEvents: [],
                authorRelayListEvents: authorRelayListEvents
            ),
            accountID: model.account.pubkey
        )
        return content
    }

    private static func projection(
        model: ModelFixture
    ) -> HomeFeedProjectionController {
        let projection = HomeFeedProjectionController(eventStore: nil)
        projection.activate(
            definition: model.definition,
            window: nil,
            sourceAuthors: [model.account.pubkey]
        )
        return projection
    }

    private static func packetInstaller(
        for installer: BackwardRequestPacketInstallerSpy?
    ) -> HomeTimelineBackwardRequestCoordinator.PacketInstaller? {
        if let installer {
            return { [installer] packets, mergeField in
                try await installer.install(packets, mergeField: mergeField)
            }
        }
        return nil
    }

    func definition(revision: Int) throws -> NostrFeedDefinitionRecord {
        try Self.definition(accountID: account.pubkey, revision: revision)
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

@MainActor
private final class BackwardRequestGapStatePersistenceSpy:
    HomeTimelineGapRequestStatePersisting {
    enum Event: Equatable {
        case requested(
            newerEventID: String,
            olderEventID: String,
            feedID: String
        )
        case unresolved(
            newerEventID: String,
            olderEventID: String,
            feedID: String
        )
    }

    private(set) var events: [Event] = []

    func markGapRequested(
        newerEventID: String,
        olderEventID: String,
        definition: NostrFeedDefinitionRecord
    ) throws {
        events.append(.requested(
            newerEventID: newerEventID,
            olderEventID: olderEventID,
            feedID: definition.feedID
        ))
    }

    func markGapUnresolved(
        _ gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) {
        events.append(.unresolved(
            newerEventID: gap.newerPostID,
            olderEventID: gap.olderPostID,
            feedID: context.feedID
        ))
    }
}

@MainActor
private final class BackwardRequestPacketInstallerSpy {
    struct Installation: Equatable {
        let packets: [NostrREQPacket]
        let mergeField: NostrREQMergeField
    }

    enum Failure: LocalizedError {
        case installationFailed

        var errorDescription: String? {
            "installation failed"
        }
    }

    var beforeReturning: (@MainActor @Sendable () -> Void)?
    private let error: Failure?
    private let throwsCancellation: Bool
    private(set) var installations: [Installation] = []

    init(
        error: Failure? = nil,
        throwsCancellation: Bool = false
    ) {
        self.error = error
        self.throwsCancellation = throwsCancellation
    }

    func install(
        _ packets: [NostrREQPacket],
        mergeField: NostrREQMergeField
    ) async throws {
        installations.append(Installation(packets: packets, mergeField: mergeField))
        beforeReturning?()
        if throwsCancellation {
            throw CancellationError()
        }
        if let error {
            throw error
        }
    }
}
