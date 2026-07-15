import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home state context factory")
@MainActor
struct HomeStateContextFactoryTests {
    @Test("One context reads the current projection on every access")
    func contextKeepsProjectionLive() {
        let fixture = StateContextFactoryFixture()
        let context = fixture.factory.context()

        #expect(
            context.effects.environment.projection() ==
                fixture.initialProjection
        )

        fixture.probe.projection = fixture.replacementProjection
        #expect(
            context.effects.environment.projection() ==
                fixture.replacementProjection
        )

        fixture.probe.projection = nil
        #expect(context.effects.environment.projection() == nil)
    }

    @Test("State applications route through the injected sink")
    func contextRoutesApplications() {
        let fixture = StateContextFactoryFixture()
        let context = fixture.factory.context()

        context.effects.apply(.scheduleMaterialization(
            delayNanoseconds: 120,
            allowsRealtimeFollow: true
        ))
        context.effects.apply(.materializeEntries)

        #expect(fixture.probe.events == [
            .scheduleMaterialization(
                delayNanoseconds: 120,
                allowsRealtimeFollow: true
            ),
            .materializeEntries
        ])
    }
}

@MainActor
private final class StateContextFactoryProbe {
    enum Event: Equatable {
        case scheduleMaterialization(
            delayNanoseconds: UInt64?,
            allowsRealtimeFollow: Bool?
        )
        case materializeEntries
        case other
    }

    var projection: HomeTimelineStateContextProjection?
    private(set) var events: [Event] = []

    init(projection: HomeTimelineStateContextProjection) {
        self.projection = projection
    }

    var environment: HomeStateContextEnvironment {
        HomeStateContextEnvironment(
            projection: { [self] in projection },
            apply: { [self] application in
                events.append(Self.event(for: application))
            }
        )
    }

    private static func event(
        for application: HomeTimelineStateInteractionApplication
    ) -> Event {
        switch application {
        case .scheduleMaterialization(let delay, let allowsRealtimeFollow):
            .scheduleMaterialization(
                delayNanoseconds: delay,
                allowsRealtimeFollow: allowsRealtimeFollow
            )
        case .materializeEntries:
            .materializeEntries
        default:
            .other
        }
    }
}

@MainActor
private struct StateContextFactoryFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "state-context",
        readOnly: true
    )
    let probe: StateContextFactoryProbe
    let factory: HomeStateContextFactory

    init() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "state-context",
            readOnly: true
        )
        let probe = StateContextFactoryProbe(
            projection: Self.projection(
                account: account,
                accountID: account.pubkey,
                hasPendingEvents: true
            )
        )
        self.probe = probe
        factory = HomeStateContextFactory(environment: probe.environment)
    }

    var initialProjection: HomeTimelineStateContextProjection {
        Self.projection(
            account: account,
            accountID: account.pubkey,
            hasPendingEvents: true
        )
    }

    var replacementProjection: HomeTimelineStateContextProjection {
        Self.projection(
            account: nil,
            accountID: "replacement",
            hasPendingEvents: false
        )
    }

    private static func projection(
        account: NostrAccount?,
        accountID: String,
        hasPendingEvents: Bool
    ) -> HomeTimelineStateContextProjection {
        HomeTimelineStateContextProjection(
            persistenceState: HomeTimelinePersistenceState(
                accountID: accountID,
                followedPubkeys: [accountID]
            ),
            runtimeApplicationState: HomeTimelineRuntimeApplicationState(
                account: account,
                resolvedRelays: ["wss://relay.example"],
                followedPubkeys: [accountID],
                nip05Resolutions: [:],
                hasMoreOlder: hasPendingEvents,
                deferredMaterializationDelayNanoseconds: 240
            ),
            hasPendingEvents: hasPendingEvents
        )
    }
}
