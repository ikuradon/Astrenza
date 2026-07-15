import AstrenzaCore
@testable import Astrenza

@MainActor
final class RuntimeSessionPumpSpy: HomeTimelineRuntimeEventPumping {
    var startResults = [true]
    private(set) var streamProviders: [HomeTimelineRuntimeEventPump.StreamProvider] = []
    private(set) var sourceValidities: [HomeTimelineRuntimeEventPump.SourceValidity] = []
    private(set) var packetHandlers: [HomeTimelineRuntimeEventPump.PacketHandler] = []
    private(set) var cancelCount = 0

    func start(
        stream: @escaping HomeTimelineRuntimeEventPump.StreamProvider,
        isSourceCurrent: @escaping HomeTimelineRuntimeEventPump.SourceValidity,
        onPacket: @escaping HomeTimelineRuntimeEventPump.PacketHandler
    ) -> Bool {
        streamProviders.append(stream)
        sourceValidities.append(isSourceCurrent)
        packetHandlers.append(onPacket)
        return startResults.indices.contains(streamProviders.count - 1)
            ? startResults[streamProviders.count - 1]
            : false
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
final class RuntimeSessionProfileObserverSpy: HomeTimelineProfileUpdateObserving {
    var startResults = [true]
    private(set) var relayLists: [[String]] = []
    private(set) var updateHandlers: [
        HomeTimelineDependencyResolutionCoordinator.ProfileUpdateHandler
    ] = []
    private(set) var stopCount = 0

    func startProfileUpdates(
        relayURLs: [String],
        onUpdate: @escaping HomeTimelineDependencyResolutionCoordinator.ProfileUpdateHandler
    ) -> Bool {
        relayLists.append(relayURLs)
        updateHandlers.append(onUpdate)
        return startResults.indices.contains(relayLists.count - 1)
            ? startResults[relayLists.count - 1]
            : false
    }

    func stopProfileUpdates() async {
        stopCount += 1
    }
}

@MainActor
final class RuntimeSessionProfileApplicationSpy: HomeTimelineProfileUpdateApplying {
    var replacementEvent: NostrEvent?
    private(set) var rememberedEvents: [NostrEvent] = []
    private(set) var consultEventStoreValues: [Bool] = []
    private(set) var resolvedEvents: [NostrEvent] = []
    private(set) var contexts: [HomeTimelineRuntimeEventApplicationContext] = []

    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool,
        effects: HomeTimelineRuntimeApplicationEffects
    ) -> NostrEvent {
        rememberedEvents.append(event)
        consultEventStoreValues.append(consultEventStore)
        return replacementEvent ?? event
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        effects: HomeTimelineRuntimeApplicationEffects
    ) {
        resolvedEvents.append(metadataEvent)
        contexts.append(context)
    }
}

@MainActor
final class RuntimeSessionHandlerProbe {
    var isAccountCurrent = true
    private(set) var packets: [NostrRelayRuntimePacket] = []
    private(set) var commands: [HomeTimelineRuntimeSessionCommand] = []

    var handlers: HomeTimelineRuntimeSessionHandlers {
        HomeTimelineRuntimeSessionHandlers(
            isAccountCurrent: { [self] _ in isAccountCurrent },
            handlePacket: { [self] packet in packets.append(packet) },
            applicationEffects: Self.applicationEffects,
            perform: { [self] command in commands.append(command) }
        )
    }

    private static var applicationEffects: HomeTimelineRuntimeApplicationEffects {
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

@MainActor
struct RuntimeSessionTestSystem {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleCoordinator
    let lifecycleToken: HomeTimelineLifecycleToken
    let pump: RuntimeSessionPumpSpy
    let profileObserver: RuntimeSessionProfileObserverSpy
    let profileApplication: RuntimeSessionProfileApplicationSpy
    let coordinator: HomeTimelineRuntimeSessionCoordinator
    let probe = RuntimeSessionHandlerProbe()

    init(hasRuntimeStream: Bool = true) {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        let lifecycle = HomeTimelineLifecycleCoordinator()
        let lifecycleToken = lifecycle.begin(accountID: account.pubkey)
        let pump = RuntimeSessionPumpSpy()
        let profileObserver = RuntimeSessionProfileObserverSpy()
        let profileApplication = RuntimeSessionProfileApplicationSpy()
        let runtimeStream: HomeTimelineRuntimeSessionCoordinator.RuntimeStream?
        if hasRuntimeStream {
            runtimeStream = {
                AsyncStream { continuation in continuation.finish() }
            }
        } else {
            runtimeStream = nil
        }

        self.account = account
        self.lifecycle = lifecycle
        self.lifecycleToken = lifecycleToken
        self.pump = pump
        self.profileObserver = profileObserver
        self.profileApplication = profileApplication
        self.coordinator = HomeTimelineRuntimeSessionCoordinator(
            runtimeEventPump: pump,
            runtimeStream: runtimeStream,
            profileUpdateObserver: profileObserver,
            profileUpdateApplication: profileApplication,
            lifecycleCoordinator: lifecycle
        )
    }

    func request(
        includesAccount: Bool = true,
        hasRelayRuntime: Bool = true,
        isTerminating: Bool = false
    ) -> HomeTimelineRuntimeSessionRequest {
        HomeTimelineRuntimeSessionRequest(
            account: includesAccount ? account : nil,
            profileRelayURLs: ["wss://profile.example"],
            hasRelayRuntime: hasRelayRuntime,
            isTerminating: isTerminating
        )
    }

    static func metadataEvent(
        idCharacter: Character = "1",
        pubkey: String
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(idCharacter), count: 64),
            pubkey: pubkey,
            createdAt: idCharacter == "1" ? 100 : 200,
            kind: 0,
            tags: [],
            content: #"{"name":"Alice"}"#,
            sig: String(repeating: "0", count: 128)
        )
    }
}
