import Foundation
import NostrCryptoAPI
import NostrProtocol
import NostrStoreAPI
import NostrStoreGRDB

public struct NostrPublisher {
    private let store: NostrEventStore
    private let signer: any NostrEventSigning
    private let clock: @Sendable () -> Int
    private let localID: @Sendable () -> String

    public init(
        store: NostrEventStore,
        signer: any NostrEventSigning,
        clock: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) },
        localID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.store = store
        self.signer = signer
        self.clock = clock
        self.localID = localID
    }

    @discardableResult
    public func enqueue(
        _ input: NostrPublishInput,
        accountID: String,
        relayURLs: [String],
        taggedUserReadRelays: [String] = [],
        fallbackRelays: [String] = []
    ) async throws -> NostrOutboxEventRecord {
        let createdAt = clock()
        let unsignedEvent = input.unsignedEvent(pubkey: accountID, createdAt: createdAt)
        let signedEvent = try await signer.sign(unsignedEvent)
        let relays = NostrPublishDestinationResolver.relayDestinations(
            accountWriteRelays: relayURLs,
            taggedUserReadRelays: taggedUserReadRelays,
            fallbackRelays: fallbackRelays
        )
        return try store.enqueueOutboxEvent(
            signedEvent,
            accountID: accountID,
            relayURLs: relays,
            localID: localID(),
            createdAt: createdAt
        )
    }
}
