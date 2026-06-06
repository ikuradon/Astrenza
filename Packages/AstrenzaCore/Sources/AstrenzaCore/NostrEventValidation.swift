import Foundation
import secp256k1

public struct NostrEventValidator: Sendable {
    public init() {}

    public func isValid(_ event: NostrEvent) -> Bool {
        guard event.hasValidShape,
              var messageBytes = NostrHex.bytes(fromLowercaseHex: event.id),
              var pubkeyBytes = NostrHex.bytes(fromLowercaseHex: event.pubkey),
              var signatureBytes = NostrHex.bytes(fromLowercaseHex: event.sig)
        else { return false }

        let context = secp256k1.Context.raw
        var xonlyPubkey = secp256k1_xonly_pubkey()
        guard secp256k1_xonly_pubkey_parse(context, &xonlyPubkey, &pubkeyBytes) != 0 else {
            return false
        }

        return secp256k1_schnorrsig_verify(
            context,
            &signatureBytes,
            &messageBytes,
            messageBytes.count,
            &xonlyPubkey
        ) > 0
    }
}
