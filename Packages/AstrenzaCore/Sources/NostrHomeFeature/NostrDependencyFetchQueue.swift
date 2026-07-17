import Foundation
import NostrRelay

public struct NostrDependencyFetchPolicy: Equatable, Sendable {
    public let profileStaleAfterSeconds: Int
    public let retryAfterSeconds: Int

    public init(
        profileStaleAfterSeconds: Int = 24 * 60 * 60,
        retryAfterSeconds: Int = 15 * 60
    ) {
        self.profileStaleAfterSeconds = max(0, profileStaleAfterSeconds)
        self.retryAfterSeconds = max(0, retryAfterSeconds)
    }
}

public struct NostrDependencyFetchCacheSnapshot: Equatable, Sendable {
    public let profileReceivedAtByPubkey: [String: Int]
    public let sourceEventIDs: Set<String>

    public init(
        profileReceivedAtByPubkey: [String: Int] = [:],
        sourceEventIDs: Set<String> = []
    ) {
        self.profileReceivedAtByPubkey = profileReceivedAtByPubkey
        self.sourceEventIDs = sourceEventIDs
    }
}

public struct NostrDependencyFetchGroup: Equatable, Sendable {
    public let relayURLs: [String]
    public let values: [String]

    public init(relayURLs: [String], values: [String]) {
        self.relayURLs = relayURLs
        self.values = values
    }
}

public struct NostrDependencyFetchBatch: Equatable, Sendable {
    public let profileGroups: [NostrDependencyFetchGroup]
    public let sourceGroups: [NostrDependencyFetchGroup]

    public var isEmpty: Bool {
        profileGroups.isEmpty && sourceGroups.isEmpty
    }

    public init(
        profileGroups: [NostrDependencyFetchGroup] = [],
        sourceGroups: [NostrDependencyFetchGroup] = []
    ) {
        self.profileGroups = profileGroups
        self.sourceGroups = sourceGroups
    }
}

public struct NostrDependencyFetchQueue: Equatable, Sendable {
    private struct RelaySelectionKey: Hashable, Sendable {
        let relayURLs: [String]
    }

    public private(set) var pendingProfilePubkeys = Set<String>()
    public private(set) var pendingSourceEventIDs = Set<String>()

    private var bufferedProfilePubkeysByRelay: [RelaySelectionKey: Set<String>] = [:]
    private var bufferedSourceEventIDsByRelay: [RelaySelectionKey: Set<String>] = [:]
    private var retryAfterByProfilePubkey: [String: Int] = [:]
    private var retryAfterBySourceEventID: [String: Int] = [:]
    private let policy: NostrDependencyFetchPolicy

    public init(policy: NostrDependencyFetchPolicy = NostrDependencyFetchPolicy()) {
        self.policy = policy
    }

    public var hasPendingWork: Bool {
        !pendingProfilePubkeys.isEmpty ||
            !pendingSourceEventIDs.isEmpty ||
            !bufferedProfilePubkeysByRelay.isEmpty ||
            !bufferedSourceEventIDsByRelay.isEmpty
    }

    public mutating func removeAll() {
        pendingProfilePubkeys.removeAll()
        pendingSourceEventIDs.removeAll()
        bufferedProfilePubkeysByRelay.removeAll()
        bufferedSourceEventIDsByRelay.removeAll()
        retryAfterByProfilePubkey.removeAll()
        retryAfterBySourceEventID.removeAll()
    }

    @discardableResult
    public mutating func enqueue(
        dependencies: NostrEventDependencies,
        cacheSnapshot: NostrDependencyFetchCacheSnapshot,
        availableRelayURLs: [String],
        availableProfileRelayURLs: [String]? = nil,
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> Bool {
        let missingProfiles = dependencies.profilePubkeys.filter { pubkey in
            shouldFetchProfile(
                pubkey: pubkey,
                cacheSnapshot: cacheSnapshot,
                now: now
            )
        }
        let missingSourceIDs = dependencies.sourceEventIDs.filter { eventID in
            shouldFetchSourceEvent(
                eventID: eventID,
                cacheSnapshot: cacheSnapshot,
                now: now
            )
        }

        guard !missingProfiles.isEmpty || !missingSourceIDs.isEmpty else { return false }

        let profileGroups = groupedDependencies(
            missingProfiles,
            availableRelayURLs: availableProfileRelayURLs ?? availableRelayURLs,
            hintsForValue: { dependencies.profileRelayURLsByPubkey[$0] ?? [] }
        )
        for (relayURLs, pubkeys) in profileGroups {
            bufferedProfilePubkeysByRelay[RelaySelectionKey(relayURLs: relayURLs), default: []].formUnion(pubkeys)
        }
        let sourceGroups = groupedDependencies(
            missingSourceIDs,
            availableRelayURLs: availableRelayURLs,
            hintsForValue: { dependencies.sourceRelayURLsByEventID[$0] ?? [] }
        )
        for (relayURLs, ids) in sourceGroups {
            bufferedSourceEventIDsByRelay[RelaySelectionKey(relayURLs: relayURLs), default: []].formUnion(ids)
        }

        return !profileGroups.isEmpty || !sourceGroups.isEmpty
    }

    public mutating func drain() -> NostrDependencyFetchBatch {
        let profileGroups = bufferedProfilePubkeysByRelay
            .map { key, values in NostrDependencyFetchGroup(relayURLs: key.relayURLs, values: Array(values).sorted()) }
            .filter { !$0.values.isEmpty }
            .sorted { $0.relayURLs.lexicographicallyPrecedes($1.relayURLs) }
        let sourceGroups = bufferedSourceEventIDsByRelay
            .map { key, values in NostrDependencyFetchGroup(relayURLs: key.relayURLs, values: Array(values).sorted()) }
            .filter { !$0.values.isEmpty }
            .sorted { $0.relayURLs.lexicographicallyPrecedes($1.relayURLs) }

        bufferedProfilePubkeysByRelay.removeAll()
        bufferedSourceEventIDsByRelay.removeAll()
        profileGroups.forEach { pendingProfilePubkeys.formUnion($0.values) }
        sourceGroups.forEach { pendingSourceEventIDs.formUnion($0.values) }

        return NostrDependencyFetchBatch(profileGroups: profileGroups, sourceGroups: sourceGroups)
    }

    public mutating func finish(
        profilePubkeys: [String] = [],
        sourceEventIDs: [String] = [],
        succeeded: Bool,
        now: Int = Int(Date().timeIntervalSince1970)
    ) {
        profilePubkeys.forEach { pubkey in
            pendingProfilePubkeys.remove(pubkey)
            if succeeded {
                retryAfterByProfilePubkey.removeValue(forKey: pubkey)
            } else {
                retryAfterByProfilePubkey[pubkey] = now + policy.retryAfterSeconds
            }
        }
        sourceEventIDs.forEach { eventID in
            pendingSourceEventIDs.remove(eventID)
            if succeeded {
                retryAfterBySourceEventID.removeValue(forKey: eventID)
            } else {
                retryAfterBySourceEventID[eventID] = now + policy.retryAfterSeconds
            }
        }
    }

    private func shouldFetchProfile(
        pubkey: String,
        cacheSnapshot: NostrDependencyFetchCacheSnapshot,
        now: Int
    ) -> Bool {
        guard retryAfterByProfilePubkey[pubkey, default: 0] <= now,
              !pendingProfilePubkeys.contains(pubkey)
        else {
            return false
        }

        guard let receivedAt = cacheSnapshot.profileReceivedAtByPubkey[pubkey] else {
            return true
        }
        return now - receivedAt >= policy.profileStaleAfterSeconds
    }

    private func shouldFetchSourceEvent(
        eventID: String,
        cacheSnapshot: NostrDependencyFetchCacheSnapshot,
        now: Int
    ) -> Bool {
        guard retryAfterBySourceEventID[eventID, default: 0] <= now,
              !pendingSourceEventIDs.contains(eventID)
        else {
            return false
        }
        return !cacheSnapshot.sourceEventIDs.contains(eventID)
    }

    private func groupedDependencies(
        _ values: [String],
        availableRelayURLs: [String],
        hintsForValue: (String) -> [String]
    ) -> [(relayURLs: [String], values: [String])] {
        var groups: [RelaySelectionKey: [String]] = [:]
        for value in values {
            let relayURLs = relaySelection(
                hintedRelayURLs: hintsForValue(value),
                availableRelayURLs: availableRelayURLs
            )
            guard !relayURLs.isEmpty else { continue }
            groups[RelaySelectionKey(relayURLs: relayURLs), default: []].append(value)
        }
        return groups
            .map { key, values in (relayURLs: key.relayURLs, values: Array(Set(values)).sorted()) }
            .sorted { lhs, rhs in lhs.relayURLs.lexicographicallyPrecedes(rhs.relayURLs) }
    }

    private func relaySelection(
        hintedRelayURLs: [String],
        availableRelayURLs: [String]
    ) -> [String] {
        hintedRelayURLs.isEmpty ? availableRelayURLs : hintedRelayURLs
    }
}
