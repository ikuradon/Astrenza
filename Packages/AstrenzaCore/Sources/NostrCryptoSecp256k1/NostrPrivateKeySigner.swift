import NostrCryptoAPI
import NostrProtocol
@preconcurrency import secp256k1

public struct NostrPrivateKeySigner: NostrEventSigning {
    private let privateKey: secp256k1.Signing.PrivateKey
    public let pubkey: String

    public init(privateKeyHex: String) throws {
        guard let bytes = NostrHex.bytes(fromLowercaseHex: privateKeyHex), bytes.count == 32 else {
            throw NostrSigningError.invalidPrivateKey
        }
        privateKey = try secp256k1.Signing.PrivateKey(rawRepresentation: bytes)
        pubkey = NostrHex.hexString(Array(privateKey.publicKey.xonly.bytes))
    }

    public func sign(_ unsignedEvent: NostrUnsignedEvent) async throws -> NostrEvent {
        guard unsignedEvent.pubkey == pubkey else {
            throw NostrSigningError.pubkeyMismatch(expected: unsignedEvent.pubkey, actual: pubkey)
        }
        guard var message = NostrHex.bytes(fromLowercaseHex: unsignedEvent.eventID) else {
            throw NostrSigningError.invalidPrivateKey
        }
        let signature = try privateKey.schnorr.signature(message: &message, auxiliaryRand: nil)
        return NostrEvent(
            id: unsignedEvent.eventID,
            pubkey: unsignedEvent.pubkey,
            createdAt: unsignedEvent.createdAt,
            kind: unsignedEvent.kind,
            tags: unsignedEvent.tags,
            content: unsignedEvent.content,
            sig: NostrHex.hexString(Array(signature.rawRepresentation))
        )
    }
}
