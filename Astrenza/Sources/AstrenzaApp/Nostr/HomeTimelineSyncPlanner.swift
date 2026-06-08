import Foundation
import AstrenzaCore

struct HomeTimelineSyncPlanner {
    func forwardPacket(
        account: NostrAccount,
        followedPubkeys: [String],
        newestCreatedAt: Int?,
        relayURLs: [String]
    ) -> NostrREQPacket {
        NostrHomeForwardREQBuilder.reconnectPacket(
            authors: followedPubkeys.isEmpty ? [account.pubkey] : followedPubkeys,
            newestCreatedAt: newestCreatedAt,
            relayURLs: relayURLs
        )
    }
}
