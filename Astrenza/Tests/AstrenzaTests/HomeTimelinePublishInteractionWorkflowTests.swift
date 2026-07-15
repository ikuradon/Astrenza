import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline publish interaction workflow")
@MainActor
struct HomeTimelinePublishInteractionTests {
    @Test("Request, signer, result, and current account cross the boundary")
    func routesRequestAndDynamicEnvironment() async throws {
        let fixture = PublishInteractionFixture()

        let didEnqueue = try await fixture.workflow.enqueue(
            input: fixture.input,
            signer: fixture.signer,
            context: fixture.context
        )

        #expect(didEnqueue)
        #expect(fixture.handler.requests == [fixture.request])
        #expect(fixture.handler.receivedExpectedSigner)
        let effects = try #require(fixture.handler.effects)
        #expect(effects.currentAccountID() == fixture.account.pubkey)

        fixture.probe.currentAccountID = nil
        #expect(effects.currentAccountID() == nil)
    }

    @Test("Every publish mutation uses one typed boundary")
    func routesEveryApplicationEffect() async throws {
        let fixture = PublishInteractionFixture()

        _ = try await fixture.workflow.enqueue(
            input: fixture.input,
            signer: fixture.signer,
            context: fixture.context
        )
        let effects = try #require(fixture.handler.effects)
        effects.applyContentSnapshot(fixture.contentSnapshot)
        effects.reloadNewestProjectionWindow(fixture.account)
        effects.materializeEntries()
        await effects.persistDatabase(fixture.account)
        effects.setPhase(.loaded)

        #expect(fixture.probe.actions == [
            .applyContentSnapshot(fixture.contentSnapshot),
            .reloadNewestProjectionWindow(fixture.account),
            .materializeEntries,
            .setPhase(.loaded)
        ])
        #expect(fixture.probe.asyncActions == [
            .persistDatabase(fixture.account)
        ])
    }
}

@MainActor
private final class PublishInteractionHandlerSpy:
    HomeTimelinePublishHandling {
    private(set) var requests: [HomeTimelinePublishRequest] = []
    private(set) var effects: HomeTimelinePublishEffects?
    private(set) var receivedExpectedSigner = false

    @discardableResult
    func enqueue(
        _ request: HomeTimelinePublishRequest,
        signer: any NostrEventSigning,
        effects: HomeTimelinePublishEffects
    ) async throws -> Bool {
        requests.append(request)
        receivedExpectedSigner = signer is PublishInteractionSigner
        self.effects = effects
        return true
    }
}

@MainActor
private final class PublishInteractionProbe {
    var currentAccountID: String?
    private(set) var actions: [HomeTimelinePublishStoreAction] = []
    private(set) var asyncActions: [HomeTimelinePublishAsyncAction] = []

    init(currentAccountID: String?) {
        self.currentAccountID = currentAccountID
    }

    var effects: HomeTimelinePublishInteractionEffects {
        HomeTimelinePublishInteractionEffects(
            environment: HomeTimelinePublishEnvironment(
                currentAccountID: { [self] in currentAccountID }
            ),
            apply: { [self] action in
                actions.append(action)
            },
            perform: { [self] action in
                asyncActions.append(action)
            }
        )
    }
}

@MainActor
private struct PublishInteractionFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "publish",
        readOnly: true
    )
    let input = NostrPublishInput.post(content: "published")
    let accountWriteRelays = ["wss://write.example"]
    let fallbackRelays = ["wss://fallback.example"]
    let contentSnapshot = HomeTimelineContentSnapshot.initial
    let signer = PublishInteractionSigner()
    let probe: PublishInteractionProbe
    let handler = PublishInteractionHandlerSpy()
    let workflow: HomeTimelinePublishInteractionWorkflow

    init() {
        probe = PublishInteractionProbe(currentAccountID: account.pubkey)
        workflow = HomeTimelinePublishInteractionWorkflow(publish: handler)
    }

    var request: HomeTimelinePublishRequest {
        HomeTimelinePublishRequest(
            input: input,
            account: account,
            accountWriteRelays: accountWriteRelays,
            fallbackRelays: fallbackRelays
        )
    }

    var context: HomeTimelinePublishInteractionContext {
        HomeTimelinePublishInteractionContext(
            state: HomeTimelinePublishInteractionState(
                account: account,
                accountWriteRelays: accountWriteRelays,
                fallbackRelays: fallbackRelays
            ),
            effects: probe.effects
        )
    }
}

private actor PublishInteractionSigner: NostrEventSigning {
    func sign(_ unsignedEvent: NostrUnsignedEvent) async throws -> NostrEvent {
        NostrEvent(
            id: unsignedEvent.eventID,
            pubkey: unsignedEvent.pubkey,
            createdAt: unsignedEvent.createdAt,
            kind: unsignedEvent.kind,
            tags: unsignedEvent.tags,
            content: unsignedEvent.content,
            sig: String(repeating: "1", count: 128)
        )
    }
}
