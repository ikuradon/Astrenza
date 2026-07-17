import NostrCryptoAPI
import NostrCryptoSecp256k1
import NostrProtocol
import Testing

@Suite("secp256k1 crypto contract")
struct NostrCryptoSecp256k1Tests {
    @Test("signer output passes BIP340 validation")
    func signerOutputPassesValidation() async throws {
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "21", count: 32))
        let unsigned = NostrPublishInput.post(content: "signed")
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 900)

        let event = try await signer.sign(unsigned)

        #expect(event.id == unsigned.eventID)
        #expect(event.pubkey == signer.pubkey)
        #expect(NostrEventValidator().isValid(event))
    }

    @Test("validator rejects content tampering")
    func validatorRejectsTampering() async throws {
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "22", count: 32))
        let event = try await signer.sign(
            NostrPublishInput.post(content: "original")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 901)
        )
        let tampered = NostrEvent(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: event.createdAt,
            kind: event.kind,
            tags: event.tags,
            content: "tampered",
            sig: event.sig
        )

        #expect(!NostrEventValidator().isValid(tampered))
    }
}
