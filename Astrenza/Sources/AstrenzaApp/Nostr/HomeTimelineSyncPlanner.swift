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

struct HomeTimelineBackwardPacketPlan {
    let primaryPackets: [NostrREQPacket]
    let hedgePackets: [NostrREQPacket]
    let requestedLimit: Int

    var hasHedge: Bool {
        !hedgePackets.isEmpty
    }
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
        olderNotesPlan(
            account: account,
            followedPubkeys: followedPubkeys,
            oldestCreatedAt: oldestCreatedAt,
            relayURLs: relayURLs,
            contactItems: contactItems,
            authorRelayListEvents: authorRelayListEvents,
            policy: policy,
            limit: limit,
            requestID: requestID
        )?.primaryPackets.first
    }

    func olderNotesPlan(
        account: NostrAccount,
        followedPubkeys: [String],
        oldestCreatedAt: Int,
        relayURLs: [String],
        contactItems: [NostrContactListItem] = [],
        authorRelayListEvents: [NostrEvent] = [],
        observedRelayURLsByAuthor: [String: [String]] = [:],
        policy: NostrSyncPolicy = .default(),
        limit: Int = 100,
        requestID: String = UUID().uuidString
    ) -> HomeTimelineBackwardPacketPlan? {
        let authors = timelineAuthors(
            account: account,
            followedPubkeys: followedPubkeys
        )
        let safeLimit = max(1, limit)
        guard policy.mode == .fullOutbox else {
            guard let packet = NostrBackwardREQBuilder.olderNotes(
                authors: authors,
                until: oldestCreatedAt - 1,
                limit: safeLimit,
                relayURLs: relayURLs,
                requestID: requestID
            ) else { return nil }
            return HomeTimelineBackwardPacketPlan(
                primaryPackets: [packet],
                hedgePackets: [],
                requestedLimit: safeLimit
            )
        }

        return fullOutboxBackwardPlan(
            authors: authors,
            contactItems: contactItems,
            authorRelayListEvents: authorRelayListEvents,
            observedRelayURLsByAuthor: observedRelayURLsByAuthor,
            fallbackRelayURLs: relayURLs,
            primaryGroupID: "astrenza-older-notes-\(requestID)",
            hedgeGroupID: "astrenza-older-notes-\(requestID)-hedge",
            requestedLimit: safeLimit
        ) { scopedAuthors in
            [[
                "kinds": .ints([1, 5, 6]),
                "authors": .strings(scopedAuthors),
                "until": .int(max(0, oldestCreatedAt - 1)),
                "limit": .int(safeLimit)
            ]]
        }
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
        gapNotesPlan(
            account: account,
            followedPubkeys: followedPubkeys,
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            missingEstimate: missingEstimate,
            relayURLs: relayURLs,
            contactItems: contactItems,
            authorRelayListEvents: authorRelayListEvents,
            policy: policy,
            requestID: requestID
        )?.primaryPackets.first
    }

    func gapNotesPlan(
        account: NostrAccount,
        followedPubkeys: [String],
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        missingEstimate: Int,
        relayURLs: [String],
        contactItems: [NostrContactListItem] = [],
        authorRelayListEvents: [NostrEvent] = [],
        observedRelayURLsByAuthor: [String: [String]] = [:],
        policy: NostrSyncPolicy = .default(),
        requestID: String = UUID().uuidString
    ) -> HomeTimelineBackwardPacketPlan? {
        let authors = timelineAuthors(
            account: account,
            followedPubkeys: followedPubkeys
        )
        let safeSince = max(0, olderEvent.createdAt + 1)
        let safeUntil = max(0, newerEvent.createdAt - 1)
        let safeLimit = max(1, min(missingEstimate, 250))
        guard safeSince <= safeUntil else { return nil }
        guard policy.mode == .fullOutbox else {
            guard let packet = NostrBackwardREQBuilder.notesWindow(
                authors: authors,
                since: safeSince,
                until: safeUntil,
                limit: safeLimit,
                relayURLs: relayURLs,
                requestID: requestID
            ) else { return nil }
            return HomeTimelineBackwardPacketPlan(
                primaryPackets: [packet],
                hedgePackets: [],
                requestedLimit: safeLimit
            )
        }

        return fullOutboxBackwardPlan(
            authors: authors,
            contactItems: contactItems,
            authorRelayListEvents: authorRelayListEvents,
            observedRelayURLsByAuthor: observedRelayURLsByAuthor,
            fallbackRelayURLs: relayURLs,
            primaryGroupID: "astrenza-gap-notes-\(requestID)",
            hedgeGroupID: "astrenza-gap-notes-\(requestID)-hedge",
            requestedLimit: safeLimit
        ) { scopedAuthors in
            [[
                "kinds": .ints([1, 5, 6]),
                "authors": .strings(scopedAuthors),
                "since": .int(safeSince),
                "until": .int(safeUntil),
                "limit": .int(safeLimit)
            ]]
        }
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

    private func fullOutboxBackwardPlan(
        authors: [String],
        contactItems: [NostrContactListItem],
        authorRelayListEvents: [NostrEvent],
        observedRelayURLsByAuthor: [String: [String]],
        fallbackRelayURLs: [String],
        primaryGroupID: String,
        hedgeGroupID: String,
        requestedLimit: Int,
        filters: ([String]) -> [[String: AnySendableJSON]]
    ) -> HomeTimelineBackwardPacketPlan? {
        let routing = NostrOutboxRelayRouting()
        let candidates = routing.relayURLsByAuthor(
            authors: authors,
            relayListEvents: authorRelayListEvents,
            contactItems: contactItems,
            observedRelayURLsByAuthor: observedRelayURLsByAuthor,
            fallbackRelayURLs: fallbackRelayURLs
        )
        let primary = candidates.mapValues { Array($0.prefix(1)) }
        let hedge = candidates.mapValues { Array($0.dropFirst()) }
        let primaryPackets = relayScopedBackwardPackets(
            relayURLsByAuthor: primary,
            groupID: primaryGroupID,
            filters: filters
        )
        guard !primaryPackets.isEmpty else { return nil }
        return HomeTimelineBackwardPacketPlan(
            primaryPackets: primaryPackets,
            hedgePackets: relayScopedBackwardPackets(
                relayURLsByAuthor: hedge,
                groupID: hedgeGroupID,
                filters: filters
            ),
            requestedLimit: requestedLimit
        )
    }

    private func relayScopedBackwardPackets(
        relayURLsByAuthor: [String: [String]],
        groupID: String,
        filters: ([String]) -> [[String: AnySendableJSON]]
    ) -> [NostrREQPacket] {
        let authorsByRelay = NostrOutboxRelayRouting().authorsByRelay(
            relayURLsByAuthor: relayURLsByAuthor
        )
        return authorsByRelay.keys.sorted().enumerated().map { index, relayURL in
            let authors = (authorsByRelay[relayURL] ?? []).sorted()
            return NostrREQPacket(
                strategy: .backward,
                subscriptionID: "\(groupID)-req-\(index + 1)",
                groupID: groupID,
                filters: filters(authors),
                relayURLs: [relayURL]
            )
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
