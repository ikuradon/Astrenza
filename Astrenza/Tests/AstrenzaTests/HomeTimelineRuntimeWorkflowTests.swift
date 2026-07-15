import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime workflow")
@MainActor
struct HomeTimelineRuntimeWorkflowTests {
    @Test("Session startup routes profile changes and runtime packets")
    func sessionRoutesEffects() async throws {
        let fixture = RuntimeWorkflowFixture()
        fixture.session.command = .profileDirectoryChanged
        let request = fixture.sessionRequest

        let result = fixture.workflow.startSession(
            request,
            effects: fixture.sessionEffects
        )

        #expect(result == fixture.session.startResult)
        #expect(fixture.session.request == request)
        #expect(fixture.session.observedAccountValidity == true)
        #expect(fixture.session.hasApplicationEffects)
        #expect(fixture.probe.profileChangeActions == [
            .invalidateListEntries,
            .scheduleMaterialization
        ])

        let packetHandler = try #require(fixture.session.packetHandler)
        await packetHandler(fixture.packet)
        #expect(fixture.packetRouter.packets == [fixture.packet])
        #expect(fixture.packetRouter.contexts == [fixture.observedContext])
    }

    @Test("Packet application routes state, events, and backward completion")
    func packetRoutesEffects() async {
        let fixture = RuntimeWorkflowFixture()
        fixture.packetRouter.application = .handled(realtimeState: true)
        fixture.packetRouter.event = fixture.event
        fixture.packetRouter.completion = fixture.completion

        await fixture.workflow.handlePacket(
            fixture.packet,
            effects: fixture.packetEffects
        )

        #expect(fixture.probe.realtimeStates == [true])
        #expect(fixture.probe.relayTransitionCount == 1)
        #expect(fixture.probe.events == [fixture.event])
        #expect(fixture.probe.completions == [fixture.completion])
    }

    @Test("A missing packet context suppresses packet routing")
    func missingPacketContextStopsRouting() async {
        let fixture = RuntimeWorkflowFixture(hasPacketContext: false)

        await fixture.workflow.handlePacket(
            fixture.packet,
            effects: fixture.packetEffects
        )

        #expect(fixture.packetRouter.packets.isEmpty)
        #expect(fixture.probe.realtimeStates.isEmpty)
        #expect(fixture.probe.relayTransitionCount == 0)
    }

    @Test("Setup commands and reset stay behind the setup effect boundary")
    func setupRoutesEffectsAndReset() async {
        let fixture = RuntimeWorkflowFixture()
        fixture.setup.commands = [
            .setRealtime(false),
            .recordDiagnostic(fixture.diagnostic)
        ]

        await fixture.workflow.configure(
            fixture.setupRequest,
            effects: fixture.setupEffects
        )
        fixture.workflow.resetSetup()

        #expect(fixture.setup.request == fixture.setupRequest)
        #expect(fixture.probe.realtimeStates == [false])
        #expect(fixture.probe.diagnostics == [fixture.diagnostic])
        #expect(fixture.setup.resetCount == 1)
    }
}

@MainActor
private final class RuntimeSessionStarterSpy:
    HomeTimelineRuntimeSessionStarting {
    var request: HomeTimelineRuntimeSessionRequest?
    var command: HomeTimelineRuntimeSessionCommand?
    var observedAccountValidity: Bool?
    var packetHandler: HomeTimelineRuntimeSessionHandlers.PacketHandler?
    var hasApplicationEffects = false
    let startResult = HomeTimelineRuntimeSessionStart(
        didStartProfileUpdates: true,
        didStartRuntimeEvents: true
    )

    func start(
        _ request: HomeTimelineRuntimeSessionRequest,
        handlers: HomeTimelineRuntimeSessionHandlers
    ) -> HomeTimelineRuntimeSessionStart {
        self.request = request
        observedAccountValidity = request.account.map {
            handlers.isAccountCurrent($0.pubkey)
        }
        packetHandler = handlers.handlePacket
        hasApplicationEffects = true
        if let command {
            handlers.perform(command)
        }
        return startResult
    }
}

@MainActor
private final class RuntimeSetupManagerSpy: HomeTimelineRuntimeSetupManaging {
    var request: HomeTimelineRuntimeSetupRequest?
    var commands: [HomeTimelineRuntimeSetupCommand] = []
    var resetCount = 0

    func reset() {
        resetCount += 1
    }

    func configure(
        _ request: HomeTimelineRuntimeSetupRequest,
        handlers: HomeTimelineRuntimeSetupHandlers
    ) async {
        self.request = request
        commands.forEach(handlers.perform)
    }
}

@MainActor
private final class RuntimePacketRouterSpy: HomeTimelineRuntimePacketRouting {
    var packets: [NostrRelayRuntimePacket] = []
    var contexts: [RuntimeWorkflowObservedContext] = []
    var application: HomeTimelineRuntimePacketApplication?
    var event: NostrEvent?
    var completion: NostrBackwardREQCompletion?

    func handle(
        _ packet: NostrRelayRuntimePacket,
        context: HomeTimelineRuntimePacketContext,
        handlers: HomeTimelineRuntimePacketHandlers
    ) async {
        packets.append(packet)
        contexts.append(RuntimeWorkflowObservedContext(
            isActive: context.isActive,
            accountID: context.accountID,
            resolvedRelays: context.resolvedRelays
        ))
        if let application {
            handlers.applyState(application)
        }
        if let event {
            await handlers.handleEvent(
                "wss://relay.example",
                "astrenza-home-forward",
                event
            )
        }
        if let completion {
            handlers.handleBackwardCompletion(completion)
        }
    }
}

private struct RuntimeWorkflowObservedContext: Equatable, Sendable {
    let isActive: Bool
    let accountID: String?
    let resolvedRelays: [String]
}

private enum RuntimeProfileChangeAction: Equatable, Sendable {
    case invalidateListEntries
    case scheduleMaterialization
}

@MainActor
private final class RuntimeWorkflowProbe {
    var profileChangeActions: [RuntimeProfileChangeAction] = []
    var realtimeStates: [Bool] = []
    var relayTransitionCount = 0
    var events: [NostrEvent] = []
    var completions: [NostrBackwardREQCompletion] = []
    var diagnostics: [HomeTimelineRuntimeSetupDiagnostic] = []
}

@MainActor
private struct RuntimeWorkflowFixture {
    let account: NostrAccount
    let resolvedRelays = ["wss://relay.example"]
    let packet = NostrRelayRuntimePacket.notice(
        relayURL: "wss://relay.example",
        message: "ready"
    )
    let event = runtimePacketEvent(idSeed: "8", createdAt: 800)
    let completion = NostrBackwardREQCompletion(
        groupID: "older-runtime-workflow",
        relayURLs: ["wss://relay.example"],
        subscriptionIDs: ["astrenza-home-older"],
        eventCount: 2,
        eoseCount: 1,
        closedCount: 0,
        timeoutCount: 0
    )
    let diagnostic = HomeTimelineRuntimeSetupDiagnostic(
        relayURL: "wss://relay.example",
        subscriptionID: "astrenza-home-forward",
        message: "install failed"
    )
    let session = RuntimeSessionStarterSpy()
    let setup = RuntimeSetupManagerSpy()
    let packetRouter = RuntimePacketRouterSpy()
    let probe = RuntimeWorkflowProbe()
    let hasPacketContext: Bool
    let workflow: HomeTimelineRuntimeWorkflow

    init(hasPacketContext: Bool = true) {
        self.hasPacketContext = hasPacketContext
        self.account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        self.workflow = HomeTimelineRuntimeWorkflow(
            session: session,
            setup: setup,
            packetRouter: packetRouter
        )
    }

    var observedContext: RuntimeWorkflowObservedContext {
        RuntimeWorkflowObservedContext(
            isActive: true,
            accountID: account.pubkey,
            resolvedRelays: resolvedRelays
        )
    }

    var sessionRequest: HomeTimelineRuntimeSessionRequest {
        HomeTimelineRuntimeSessionRequest(
            account: account,
            profileRelayURLs: resolvedRelays,
            hasRelayRuntime: true,
            isTerminating: false
        )
    }

    var setupRequest: HomeTimelineRuntimeSetupRequest {
        HomeTimelineRuntimeSetupRequest(
            account: account,
            defaultRelayURLs: resolvedRelays,
            policy: .default(networkType: .unknown, lowPowerMode: false),
            hasRelayRuntime: true,
            isTerminating: false,
            forceInstall: true
        )
    }

    var sessionEffects: HomeTimelineRuntimeSessionEffects {
        HomeTimelineRuntimeSessionEffects(
            isAccountCurrent: { [account] accountID in
                account.pubkey == accountID
            },
            application: runtimeApplicationEffects,
            packet: packetEffects,
            invalidateListEntries: { [probe] in
                probe.profileChangeActions.append(.invalidateListEntries)
            },
            scheduleMaterialization: { [probe] in
                probe.profileChangeActions.append(.scheduleMaterialization)
            }
        )
    }

    var packetEffects: HomeTimelineRuntimePacketEffects {
        HomeTimelineRuntimePacketEffects(
            context: { [hasPacketContext, account, resolvedRelays] in
                guard hasPacketContext else { return nil }
                return HomeTimelineRuntimePacketContext(
                    isActive: true,
                    accountID: account.pubkey,
                    resolvedRelays: resolvedRelays,
                    isCurrentFeedContext: { _ in true }
                )
            },
            setRealtime: { [probe] isRealtime in
                probe.realtimeStates.append(isRealtime)
            },
            applyRelayStatusTransition: { [probe] _ in
                probe.relayTransitionCount += 1
            },
            handleEvent: { [probe] _, _, event in
                probe.events.append(event)
            },
            handleBackwardCompletion: { [probe] completion in
                probe.completions.append(completion)
            }
        )
    }

    var setupEffects: HomeTimelineRuntimeSetupEffects {
        HomeTimelineRuntimeSetupEffects(
            setRealtime: { [probe] isRealtime in
                probe.realtimeStates.append(isRealtime)
            },
            recordDiagnostic: { [probe] diagnostic in
                probe.diagnostics.append(diagnostic)
            }
        )
    }

    var runtimeApplicationEffects: HomeTimelineRuntimeApplicationEffects {
        HomeTimelineRuntimeApplicationEffects(
            listRevisionChanged: { _ in },
            pendingCountChanged: { _ in },
            reloadProjection: { _, _ in },
            reloadNewestProjection: { _ in },
            scheduleMaterialization: { _ in },
            persistTimelineMetadata: { _ in },
            sourceInstallFailed: { _ in }
        )
    }
}
