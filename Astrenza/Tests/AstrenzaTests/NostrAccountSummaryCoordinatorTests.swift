import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Nostr account summary coordinator")
@MainActor
struct NostrAccountSummaryCoordinatorTests {
    @Test("An unchanged request reuses one batched metadata load")
    func reusesBatchedMetadataLoad() {
        let firstPubkey = String(repeating: "a", count: 64)
        let secondPubkey = String(repeating: "b", count: 64)
        let accounts = [
            NostrAccount(
                pubkey: firstPubkey,
                displayIdentifier: "first",
                readOnly: true
            ),
            NostrAccount(
                pubkey: secondPubkey,
                displayIdentifier: "second",
                readOnly: false
            )
        ]
        let metadata = accountMetadataEvent(
            idCharacter: "1",
            pubkey: firstPubkey,
            createdAt: 1_800_000_000,
            content: #"{"display_name":"Batch User"}"#
        )
        var loadedPubkeys: [Set<String>] = []
        let coordinator = NostrAccountSummaryCoordinator { _, pubkeys in
            loadedPubkeys.append(pubkeys)
            return [metadata]
        }

        let first = coordinator.summaries(
            accounts: accounts,
            selectedPubkey: firstPubkey,
            eventStore: nil,
            metadataRevision: 3
        )
        let second = coordinator.summaries(
            accounts: accounts,
            selectedPubkey: firstPubkey,
            eventStore: nil,
            metadataRevision: 3
        )

        #expect(loadedPubkeys == [Set([firstPubkey, secondPubkey])])
        #expect(first.map { $0.id } == second.map { $0.id })
        #expect(first.first?.title == "Batch User")
        #expect(first.first?.isSelected == true)
        #expect(first.last?.title == "second")
    }

    @Test("Metadata revision invalidates the cached summaries")
    func metadataRevisionInvalidatesCache() {
        let pubkey = String(repeating: "c", count: 64)
        let account = NostrAccount(
            pubkey: pubkey,
            displayIdentifier: "fallback",
            readOnly: true
        )
        let metadataEvents = ["Before", "After"].map { name in
            accountMetadataEvent(
                idCharacter: name == "Before" ? "2" : "3",
                pubkey: pubkey,
                createdAt: name == "Before" ? 100 : 200,
                content: #"{"display_name":"\#(name)"}"#
            )
        }
        var loadCount = 0
        let coordinator = NostrAccountSummaryCoordinator { _, _ in
            defer { loadCount += 1 }
            return [metadataEvents[min(loadCount, metadataEvents.count - 1)]]
        }

        let before = coordinator.summaries(
            accounts: [account],
            selectedPubkey: pubkey,
            eventStore: nil,
            metadataRevision: 0
        )
        let after = coordinator.summaries(
            accounts: [account],
            selectedPubkey: pubkey,
            eventStore: nil,
            metadataRevision: 1
        )

        #expect(loadCount == 2)
        #expect(before.first?.title == "Before")
        #expect(after.first?.title == "After")
    }
}

private func accountMetadataEvent(
    idCharacter: Character,
    pubkey: String,
    createdAt: Int,
    content: String
) -> NostrEvent {
    NostrEvent(
        id: String(repeating: idCharacter, count: 64),
        pubkey: pubkey,
        createdAt: createdAt,
        kind: 0,
        tags: [],
        content: content,
        sig: String(repeating: "f", count: 128)
    )
}
