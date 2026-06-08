import Foundation
import AstrenzaCore

struct HomeTimelineDependencyPacketPlan {
    let profilePackets: [NostrREQPacket]
    let sourcePackets: [NostrREQPacket]
    let registeredProfilePubkeys: [String]
    let registeredSourceEventIDs: [String]

    var isEmpty: Bool {
        profilePackets.isEmpty && sourcePackets.isEmpty
    }

    var registeredGroupIDs: [String] {
        (profilePackets + sourcePackets).map(\.groupID)
    }
}

struct HomeTimelineForwardPlan {
    let packets: [NostrREQPacket]
    let totalAuthorCount: Int
    let mode: NostrSyncMode
}

struct HomeTimelineSyncPlanner {
    func forwardPlan(
        account: NostrAccount,
        followedPubkeys: [String],
        newestCreatedAt: Int?,
        relayURLs: [String],
        policy: NostrSyncPolicy
    ) -> HomeTimelineForwardPlan {
        let authors = timelineAuthors(account: account, followedPubkeys: followedPubkeys)
        let packet = NostrHomeForwardREQBuilder.reconnectPacket(
            authors: authors,
            newestCreatedAt: newestCreatedAt,
            relayURLs: relayURLs
        )
        return HomeTimelineForwardPlan(
            packets: [packet],
            totalAuthorCount: authors.count,
            mode: policy.mode
        )
    }

    func forwardPacket(
        account: NostrAccount,
        followedPubkeys: [String],
        newestCreatedAt: Int?,
        relayURLs: [String]
    ) -> NostrREQPacket {
        forwardPlan(
            account: account,
            followedPubkeys: followedPubkeys,
            newestCreatedAt: newestCreatedAt,
            relayURLs: relayURLs,
            policy: .default()
        ).packets[0]
    }

    func olderNotesPacket(
        account: NostrAccount,
        followedPubkeys: [String],
        oldestCreatedAt: Int,
        relayURLs: [String],
        limit: Int = 100,
        requestID: String = UUID().uuidString
    ) -> NostrREQPacket? {
        NostrBackwardREQBuilder.olderNotes(
            authors: timelineAuthors(account: account, followedPubkeys: followedPubkeys),
            until: oldestCreatedAt - 1,
            limit: limit,
            relayURLs: relayURLs,
            requestID: requestID
        )
    }

    func gapNotesPacket(
        account: NostrAccount,
        followedPubkeys: [String],
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        missingEstimate: Int,
        relayURLs: [String],
        requestID: String = UUID().uuidString
    ) -> NostrREQPacket? {
        NostrBackwardREQBuilder.notesWindow(
            authors: timelineAuthors(account: account, followedPubkeys: followedPubkeys),
            since: olderEvent.createdAt + 1,
            until: newerEvent.createdAt - 1,
            limit: max(1, min(missingEstimate, 250)),
            relayURLs: relayURLs,
            requestID: requestID
        )
    }

    func dependencyPackets(
        batch: NostrDependencyFetchBatch,
        requestID: String = UUID().uuidString
    ) -> HomeTimelineDependencyPacketPlan {
        var profilePackets: [NostrREQPacket] = []
        var sourcePackets: [NostrREQPacket] = []
        var registeredProfilePubkeys: [String] = []
        var registeredSourceEventIDs: [String] = []

        for (index, group) in batch.profileGroups.enumerated() {
            guard let packet = NostrBackwardREQBuilder.profiles(
                authors: group.values,
                relayURLs: group.relayURLs,
                requestID: "\(requestID)-profile-\(index)"
            ) else { continue }
            registeredProfilePubkeys.append(contentsOf: group.values)
            profilePackets.append(packet)
        }

        for (index, group) in batch.sourceGroups.enumerated() {
            guard let packet = NostrBackwardREQBuilder.sourceEvents(
                ids: group.values,
                relayURLs: group.relayURLs,
                requestID: "\(requestID)-source-\(index)"
            ) else { continue }
            registeredSourceEventIDs.append(contentsOf: group.values)
            sourcePackets.append(packet)
        }

        return HomeTimelineDependencyPacketPlan(
            profilePackets: profilePackets,
            sourcePackets: sourcePackets,
            registeredProfilePubkeys: registeredProfilePubkeys,
            registeredSourceEventIDs: registeredSourceEventIDs
        )
    }

    private func timelineAuthors(account: NostrAccount, followedPubkeys: [String]) -> [String] {
        followedPubkeys.isEmpty ? [account.pubkey] : followedPubkeys
    }
}
