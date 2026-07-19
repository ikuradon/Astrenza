import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Relay settings presentation")
struct RelaySettingsViewTests {
    @MainActor
    @Test("Constructing a destination never reads the relay projection")
    func destinationConstructionIsSideEffectFree() throws {
        let eventStore = try NostrEventStore.inMemory()
        let probe = RelayProjectionLoadProbe()

        _ = RelaySettingsView(
            accountID: String(repeating: "a", count: 64),
            eventStore: eventStore,
            liveProjectionLoader: RelaySettingsLiveProjectionLoader { _, _ in
                probe.recordLoad()
                return RelaySettingsLiveProjectionSource(
                    relayListEvent: nil,
                    preferences: []
                )
            }
        )

        #expect(probe.loadCount == 0)
    }
}

private final class RelayProjectionLoadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLoadCount = 0

    var loadCount: Int {
        lock.withLock { storedLoadCount }
    }

    func recordLoad() {
        lock.withLock {
            storedLoadCount += 1
        }
    }
}
