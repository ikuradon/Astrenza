import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime session coordinator")
@MainActor
struct HomeTimelineRuntimeSessionTests {
    @Test("A current account starts both update sources and forwards packets")
    func startsCurrentAccountSources() async throws {
        let system = RuntimeSessionTestSystem()

        let result = system.coordinator.start(
            system.request(),
            handlers: system.probe.handlers
        )

        #expect(result == HomeTimelineRuntimeSessionStart(
            didStartProfileUpdates: true,
            didStartRuntimeEvents: true
        ))
        #expect(system.profileObserver.relayLists == [["wss://profile.example"]])
        let sourceValidity = try #require(system.pump.sourceValidities.first)
        #expect(sourceValidity())
        let packet = NostrRelayRuntimePacket.notice(
            relayURL: "wss://relay.example",
            message: "ready"
        )
        let packetHandler = try #require(system.pump.packetHandlers.first)
        await packetHandler(packet)
        #expect(system.probe.packets == [packet])

        _ = system.lifecycle.cancel()
        #expect(!sourceValidity())
    }

    @Test(
        "Invalid session state starts neither source",
        arguments: RuntimeSessionRejection.allCases
    )
    func rejectsInvalidSession(_ rejection: RuntimeSessionRejection) {
        let system = RuntimeSessionTestSystem()
        if rejection == .missingLifecycle {
            _ = system.lifecycle.cancel()
        }

        let result = system.coordinator.start(
            system.request(
                includesAccount: rejection != .missingAccount,
                isTerminating: rejection == .terminating
            ),
            handlers: system.probe.handlers
        )

        #expect(result == .inactive)
        #expect(system.profileObserver.relayLists.isEmpty)
        #expect(system.pump.packetHandlers.isEmpty)
    }

    @Test("Profile observation remains active without a runtime packet stream")
    func profileOnlySession() {
        let system = RuntimeSessionTestSystem(hasRuntimeStream: false)

        let result = system.coordinator.start(
            system.request(hasRelayRuntime: false),
            handlers: system.probe.handlers
        )

        #expect(result == HomeTimelineRuntimeSessionStart(
            didStartProfileUpdates: true,
            didStartRuntimeEvents: false
        ))
    }

    @Test("Profile metadata is applied in the active account lifecycle")
    func appliesProfileMetadata() throws {
        let system = RuntimeSessionTestSystem()
        let metadata = RuntimeSessionTestSystem.metadataEvent(
            pubkey: system.account.pubkey
        )
        let effectiveMetadata = RuntimeSessionTestSystem.metadataEvent(
            idCharacter: "2",
            pubkey: system.account.pubkey
        )
        system.profileApplication.replacementEvent = effectiveMetadata
        _ = system.coordinator.start(
            system.request(),
            handlers: system.probe.handlers
        )
        let updateHandler = try #require(system.profileObserver.updateHandlers.first)

        updateHandler(NostrProfileDirectoryUpdate(
            states: [system.account.pubkey: .resolved],
            metadataEvents: [metadata]
        ))

        #expect(system.profileApplication.rememberedEvents == [metadata])
        #expect(system.profileApplication.consultEventStoreValues == [false])
        #expect(system.profileApplication.resolvedEvents == [effectiveMetadata])
        let context = try #require(system.profileApplication.contexts.first)
        #expect(context.account == system.account)
        #expect(context.lifecycle == system.lifecycleToken)
        #expect(context.hasRelayRuntime)
        #expect(system.probe.commands == [
            .profileMetadataChanged,
            .profileDirectoryChanged
        ])
    }

    @Test("Profile state updates do not publish a metadata revision")
    func profileStateDoesNotPublishMetadataRevision() throws {
        let system = RuntimeSessionTestSystem()
        _ = system.coordinator.start(
            system.request(),
            handlers: system.probe.handlers
        )
        let updateHandler = try #require(
            system.profileObserver.updateHandlers.first
        )

        updateHandler(NostrProfileDirectoryUpdate(
            states: [system.account.pubkey: .fetching]
        ))

        #expect(system.probe.commands == [.profileDirectoryChanged])
    }

    @Test(
        "Stale profile updates cannot mutate presentation state",
        arguments: RuntimeSessionInvalidation.allCases
    )
    func rejectsStaleProfileUpdate(_ invalidation: RuntimeSessionInvalidation) throws {
        let system = RuntimeSessionTestSystem()
        _ = system.coordinator.start(
            system.request(),
            handlers: system.probe.handlers
        )
        let updateHandler = try #require(system.profileObserver.updateHandlers.first)
        switch invalidation {
        case .account:
            system.probe.isAccountCurrent = false
        case .lifecycle:
            _ = system.lifecycle.cancel()
        }

        updateHandler(NostrProfileDirectoryUpdate(
            metadataEvents: [RuntimeSessionTestSystem.metadataEvent(
                pubkey: system.account.pubkey
            )]
        ))

        #expect(system.profileApplication.rememberedEvents.isEmpty)
        #expect(system.profileApplication.resolvedEvents.isEmpty)
        #expect(system.probe.commands.isEmpty)
    }

    @Test("Repeated starts preserve downstream source deduplication")
    func preservesSourceDeduplication() {
        let system = RuntimeSessionTestSystem()
        system.pump.startResults = [true, false]
        system.profileObserver.startResults = [true, false]

        let first = system.coordinator.start(
            system.request(),
            handlers: system.probe.handlers
        )
        let duplicate = system.coordinator.start(
            system.request(),
            handlers: system.probe.handlers
        )

        #expect(first == HomeTimelineRuntimeSessionStart(
            didStartProfileUpdates: true,
            didStartRuntimeEvents: true
        ))
        #expect(duplicate == .inactive)
        #expect(system.profileObserver.relayLists.count == 2)
        #expect(system.pump.packetHandlers.count == 2)
    }

    @Test("Cancellation and profile shutdown delegate to their owners")
    func delegatesShutdown() async {
        let system = RuntimeSessionTestSystem()

        system.coordinator.cancelRuntimeEvents()
        await system.coordinator.stopProfileUpdates()

        #expect(system.pump.cancelCount == 1)
        #expect(system.profileObserver.stopCount == 1)
    }
}

enum RuntimeSessionRejection: CaseIterable, Sendable, CustomTestStringConvertible {
    case missingAccount
    case missingLifecycle
    case terminating

    var testDescription: String {
        switch self {
        case .missingAccount: "missing account"
        case .missingLifecycle: "missing lifecycle"
        case .terminating: "terminating"
        }
    }
}

enum RuntimeSessionInvalidation: CaseIterable, Sendable, CustomTestStringConvertible {
    case account
    case lifecycle

    var testDescription: String {
        switch self {
        case .account: "account"
        case .lifecycle: "lifecycle"
        }
    }
}
