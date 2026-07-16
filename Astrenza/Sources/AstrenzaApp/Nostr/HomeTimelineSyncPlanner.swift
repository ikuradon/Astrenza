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
    static let homeForwardGroupPrefix = NostrHomeForwardREQBuilder.subscriptionID
    private static let fullOutboxSubscriptionPrefix = NostrHomeForwardREQBuilder.subscriptionID + "-outbox"
    private static let initialForwardLimit = 250

    func forwardPlan(
        account: NostrAccount,
        followedPubkeys: [String],
        contactItems: [NostrContactListItem] = [],
        authorRelayListEvents: [NostrEvent] = [],
        newestCreatedAt: Int?,
        newestCreatedAtByRelay: [String: Int]? = nil,
        initialCreatedAt: Int? = nil,
        relayURLs: [String],
        policy: NostrSyncPolicy
    ) -> HomeTimelineForwardPlan {
        let authors = timelineAuthors(account: account, followedPubkeys: followedPubkeys)
        if policy.mode == .fullOutbox {
            let packets = fullOutboxForwardPackets(
                authors: authors,
                contactItems: contactItems,
                authorRelayListEvents: authorRelayListEvents,
                newestCreatedAt: newestCreatedAt,
                newestCreatedAtByRelay: newestCreatedAtByRelay,
                initialCreatedAt: initialCreatedAt,
                fallbackRelayURLs: relayURLs
            )
            return HomeTimelineForwardPlan(
                packets: packets,
                totalAuthorCount: authors.count,
                mode: policy.mode
            )
        }

        if let newestCreatedAtByRelay {
            if relayURLs.count == 1, let relayURL = relayURLs.first {
                let cursorCreatedAt = newestCreatedAtByRelay[relayURL] ?? initialCreatedAt
                let packet = initialLimitedPacketIfNeeded(NostrHomeForwardREQBuilder.reconnectPacket(
                    authors: authors,
                    newestCreatedAt: cursorCreatedAt,
                    relayURLs: [relayURL]
                ), cursorCreatedAt: cursorCreatedAt)
                return HomeTimelineForwardPlan(
                    packets: [packet],
                    totalAuthorCount: authors.count,
                    mode: policy.mode
                )
            }
            let packets = relayURLs.map { relayURL in
                relayScopedForwardPacket(
                    authors: authors,
                    newestCreatedAt: newestCreatedAtByRelay[relayURL] ?? initialCreatedAt,
                    relayURL: relayURL,
                    subscriptionPrefix: "\(Self.homeForwardGroupPrefix)-relay"
                )
            }
            return HomeTimelineForwardPlan(
                packets: packets,
                totalAuthorCount: authors.count,
                mode: policy.mode
            )
        }

        let packet = initialLimitedPacketIfNeeded(NostrHomeForwardREQBuilder.reconnectPacket(
            authors: authors,
            newestCreatedAt: newestCreatedAt,
            relayURLs: relayURLs
        ), cursorCreatedAt: newestCreatedAt)
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
        contactItems: [NostrContactListItem] = [],
        authorRelayListEvents: [NostrEvent] = [],
        policy: NostrSyncPolicy = .default(),
        limit: Int = 100,
        requestID: String = UUID().uuidString
    ) -> NostrREQPacket? {
        NostrBackwardREQBuilder.olderNotes(
            authors: timelineAuthors(account: account, followedPubkeys: followedPubkeys),
            until: oldestCreatedAt - 1,
            limit: limit,
            relayURLs: selectedRelayURLs(
                authors: timelineAuthors(
                    account: account,
                    followedPubkeys: followedPubkeys
                ),
                contactItems: contactItems,
                authorRelayListEvents: authorRelayListEvents,
                fallbackRelayURLs: relayURLs,
                policy: policy
            ),
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
        contactItems: [NostrContactListItem] = [],
        authorRelayListEvents: [NostrEvent] = [],
        policy: NostrSyncPolicy = .default(),
        requestID: String = UUID().uuidString
    ) -> NostrREQPacket? {
        NostrBackwardREQBuilder.notesWindow(
            authors: timelineAuthors(account: account, followedPubkeys: followedPubkeys),
            since: olderEvent.createdAt + 1,
            until: newerEvent.createdAt - 1,
            limit: max(1, min(missingEstimate, 250)),
            relayURLs: selectedRelayURLs(
                authors: timelineAuthors(
                    account: account,
                    followedPubkeys: followedPubkeys
                ),
                contactItems: contactItems,
                authorRelayListEvents: authorRelayListEvents,
                fallbackRelayURLs: relayURLs,
                policy: policy
            ),
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

    private func selectedRelayURLs(
        authors: [String],
        contactItems: [NostrContactListItem],
        authorRelayListEvents: [NostrEvent],
        fallbackRelayURLs: [String],
        policy: NostrSyncPolicy
    ) -> [String] {
        guard policy.mode == .fullOutbox else { return fallbackRelayURLs }
        let routes = NostrOutboxRelayRouting().relayURLsByAuthor(
            authors: authors,
            relayListEvents: authorRelayListEvents,
            contactItems: contactItems,
            fallbackRelayURLs: fallbackRelayURLs
        )
        var seen = Set<String>()
        return authors.flatMap { routes[$0.lowercased()] ?? [] }.filter {
            seen.insert($0).inserted
        }
    }

    private func fullOutboxForwardPackets(
        authors: [String],
        contactItems: [NostrContactListItem],
        authorRelayListEvents: [NostrEvent],
        newestCreatedAt: Int?,
        newestCreatedAtByRelay: [String: Int]?,
        initialCreatedAt: Int?,
        fallbackRelayURLs: [String]
    ) -> [NostrREQPacket] {
        let relayURLsByAuthor = NostrOutboxRelayRouting().relayURLsByAuthor(
            authors: authors,
            relayListEvents: authorRelayListEvents,
            contactItems: contactItems,
            fallbackRelayURLs: fallbackRelayURLs
        )
        var authorsByRelays: [RelaySelectionKey: [String]] = [:]
        for author in authors {
            let relayURLs = relayURLsByAuthor[author.lowercased()] ??
                fallbackRelayURLs
            authorsByRelays[RelaySelectionKey(relayURLs: relayURLs), default: []].append(author)
        }

        let groups = authorsByRelays
            .map { key, authors in (relayURLs: key.relayURLs, authors: authors) }
            .sorted { lhs, rhs in
                lhs.relayURLs.lexicographicallyPrecedes(rhs.relayURLs)
            }

        guard let newestCreatedAtByRelay else {
            return groups.enumerated().map { index, group in
                let basePacket = NostrHomeForwardREQBuilder.reconnectPacket(
                    authors: group.authors,
                    newestCreatedAt: newestCreatedAt,
                    relayURLs: group.relayURLs
                )
                let subscriptionID = "\(Self.fullOutboxSubscriptionPrefix)-\(index + 1)"
                let packet = NostrREQPacket(
                    strategy: .forward,
                    subscriptionID: subscriptionID,
                    groupID: subscriptionID,
                    filters: basePacket.filters,
                    relayURLs: basePacket.relayURLs
                )
                return initialLimitedPacketIfNeeded(packet, cursorCreatedAt: newestCreatedAt)
            }
        }

        return groups.enumerated().flatMap { index, group in
            group.relayURLs.map { relayURL in
                relayScopedForwardPacket(
                    authors: group.authors,
                    newestCreatedAt: newestCreatedAtByRelay[relayURL] ?? initialCreatedAt,
                    relayURL: relayURL,
                    subscriptionPrefix: "\(Self.fullOutboxSubscriptionPrefix)-\(index + 1)"
                )
            }
        }
    }

    private func relayScopedForwardPacket(
        authors: [String],
        newestCreatedAt: Int?,
        relayURL: String,
        subscriptionPrefix: String
    ) -> NostrREQPacket {
        let basePacket = NostrHomeForwardREQBuilder.reconnectPacket(
            authors: authors,
            newestCreatedAt: newestCreatedAt,
            relayURLs: [relayURL]
        )
        let subscriptionID = "\(subscriptionPrefix)-\(stableRelayIdentifier(relayURL))"
        let packet = NostrREQPacket(
            strategy: .forward,
            subscriptionID: subscriptionID,
            groupID: subscriptionID,
            filters: basePacket.filters,
            relayURLs: basePacket.relayURLs
        )
        return initialLimitedPacketIfNeeded(packet, cursorCreatedAt: newestCreatedAt)
    }

    private func initialLimitedPacketIfNeeded(
        _ packet: NostrREQPacket,
        cursorCreatedAt: Int?
    ) -> NostrREQPacket {
        guard cursorCreatedAt == nil else { return packet }
        let filters = packet.filters.map { filter in
            var filter = filter
            filter["limit"] = .int(Self.initialForwardLimit)
            return filter
        }
        return packet.replacing(filters: filters)
    }

    private func stableRelayIdentifier(_ relayURL: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in relayURL.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    static func isHomeForwardSubscription(_ subscriptionID: String) -> Bool {
        subscriptionID.hasPrefix(homeForwardGroupPrefix)
    }
}

private struct RelaySelectionKey: Hashable {
    let relayURLs: [String]

    init(relayURLs: [String]) {
        self.relayURLs = relayURLs
    }
}
