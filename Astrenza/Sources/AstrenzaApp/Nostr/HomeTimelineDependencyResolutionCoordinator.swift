import AstrenzaCore
import Foundation

struct HomeTimelineDependencyEnqueueResult: Sendable {
    let cachedProfiles: [NostrEvent]
    let didResolveCachedDependencies: Bool
    let didEnqueueSourceDependencies: Bool
}

@MainActor
final class HomeTimelineDependencyResolutionCoordinator {
    typealias NIP05ResolutionChangeHandler = @MainActor @Sendable () async -> Void

    private let eventIngestor: HomeTimelineEventIngestor
    private let profileDirectory: NostrProfileDirectory?
    private let nip05Resolver: any NostrNIP05Resolving
    private let syncPlanner: HomeTimelineSyncPlanner

    private var sourceQueue = NostrDependencyFetchQueue()
    private var sourceEventIDsByGroupID: [String: [String]] = [:]
    private var resolvingNIP05IdentifiersByPubkey: [String: String] = [:]
    private var latestNIP05IdentifiersByPubkey: [String: String] = [:]
    private var nip05TasksByPubkey: [String: Task<Void, Never>] = [:]
    private var lifecycleGeneration: UInt64 = 0

    private(set) var nip05Resolutions: [String: NostrNIP05Resolution] = [:]

    init(
        eventIngestor: HomeTimelineEventIngestor,
        profileDirectory: NostrProfileDirectory?,
        nip05Resolver: any NostrNIP05Resolving,
        syncPlanner: HomeTimelineSyncPlanner
    ) {
        self.eventIngestor = eventIngestor
        self.profileDirectory = profileDirectory
        self.nip05Resolver = nip05Resolver
        self.syncPlanner = syncPlanner
    }

    var hasPendingWork: Bool {
        sourceQueue.hasPendingWork || !sourceEventIDsByGroupID.isEmpty
    }

    var pendingSourceRequestCount: Int {
        sourceEventIDsByGroupID.count
    }

    func reset() {
        lifecycleGeneration &+= 1
        nip05TasksByPubkey.values.forEach { $0.cancel() }
        nip05TasksByPubkey.removeAll()
        resolvingNIP05IdentifiersByPubkey.removeAll()
        latestNIP05IdentifiersByPubkey.removeAll()
        nip05Resolutions.removeAll()
        sourceQueue.removeAll()
        sourceEventIDsByGroupID.removeAll()
    }

    func replaceNIP05Resolutions(_ resolutions: [String: NostrNIP05Resolution]) {
        nip05Resolutions = resolutions
    }

    func enqueueDependencies(
        for event: NostrEvent,
        liveMetadataEvents: [NostrEvent],
        liveNoteEventIDs: Set<String>,
        availableRelayURLs: [String],
        now: Int = Int(Date().timeIntervalSince1970)
    ) async -> HomeTimelineDependencyEnqueueResult {
        let dependencies = NostrEventDependencies.extract(from: event)
        let cacheResult = await eventIngestor.dependencyCacheResult(
            dependencies: dependencies,
            liveMetadataEvents: liveMetadataEvents,
            liveNoteEventIDs: liveNoteEventIDs,
            now: now
        )

        await ensureProfiles(for: event, dependencies: dependencies)

        let sourceDependencies = NostrEventDependencies(
            sourceEventIDs: dependencies.sourceEventIDs,
            sourceRelayURLsByEventID: dependencies.sourceRelayURLsByEventID
        )
        let didEnqueueSources = sourceQueue.enqueue(
            dependencies: sourceDependencies,
            cacheSnapshot: cacheResult.snapshot,
            availableRelayURLs: availableRelayURLs,
            now: now
        )
        return HomeTimelineDependencyEnqueueResult(
            cachedProfiles: cacheResult.cachedProfiles,
            didResolveCachedDependencies: cacheResult.snapshot.hasResolvedDependencies(
                for: dependencies
            ),
            didEnqueueSourceDependencies: didEnqueueSources
        )
    }

    func ensureProfiles(for events: [NostrEvent]) async {
        guard let profileDirectory, !events.isEmpty else { return }
        var authorPubkeys = Set<String>()
        var referencedPubkeys = Set<String>()
        var relayHintsByPubkey: [String: [String]] = [:]
        for event in events {
            authorPubkeys.insert(event.pubkey)
            let dependencies = NostrEventDependencies.extract(from: event)
            referencedPubkeys.formUnion(dependencies.profilePubkeys)
            for (pubkey, relayHints) in dependencies.profileRelayURLsByPubkey {
                relayHintsByPubkey[pubkey, default: []].append(contentsOf: relayHints)
            }
        }
        referencedPubkeys.subtract(authorPubkeys)
        await profileDirectory.ensureProfiles(
            pubkeys: authorPubkeys.sorted(),
            relayHintsByPubkey: relayHintsByPubkey,
            priority: .foreground
        )
        if !referencedPubkeys.isEmpty {
            await profileDirectory.ensureProfiles(
                pubkeys: referencedPubkeys.sorted(),
                relayHintsByPubkey: relayHintsByPubkey,
                priority: .background
            )
        }
    }

    @discardableResult
    func enqueueSourceDependencies(
        _ dependencies: NostrEventDependencies,
        cacheSnapshot: NostrDependencyFetchCacheSnapshot,
        availableRelayURLs: [String],
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> Bool {
        sourceQueue.enqueue(
            dependencies: NostrEventDependencies(
                sourceEventIDs: dependencies.sourceEventIDs,
                sourceRelayURLsByEventID: dependencies.sourceRelayURLsByEventID
            ),
            cacheSnapshot: cacheSnapshot,
            availableRelayURLs: availableRelayURLs,
            now: now
        )
    }

    func drainSourcePacketPlan(requestID: String = UUID().uuidString) -> HomeTimelineDependencyPacketPlan {
        let batch = sourceQueue.drain()
        let sourceBatch = NostrDependencyFetchBatch(sourceGroups: batch.sourceGroups)
        let plan = syncPlanner.dependencyPackets(batch: sourceBatch, requestID: requestID)
        for (packet, group) in zip(plan.sourcePackets, sourceBatch.sourceGroups) {
            sourceEventIDsByGroupID[packet.groupID] = group.values
        }
        return plan
    }

    func failSourceRequests(in plan: HomeTimelineDependencyPacketPlan) {
        let eventIDs = plan.registeredGroupIDs.flatMap { groupID in
            sourceEventIDsByGroupID.removeValue(forKey: groupID) ?? []
        }
        sourceQueue.finish(sourceEventIDs: eventIDs, succeeded: false)
    }

    func finishSourceEvent(eventID: String) {
        sourceQueue.finish(sourceEventIDs: [eventID], succeeded: true)
    }

    @discardableResult
    func completeSourceRequest(_ completion: NostrBackwardREQCompletion) -> Bool {
        guard let eventIDs = sourceEventIDsByGroupID.removeValue(forKey: completion.groupID) else {
            return false
        }
        sourceQueue.finish(
            sourceEventIDs: eventIDs,
            succeeded: completion.status == .completed || completion.status == .partial
        )
        return true
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        onChange: @escaping NIP05ResolutionChangeHandler
    ) {
        guard let metadata = profileMetadata(from: metadataEvent) else { return }
        let pubkey = metadataEvent.pubkey
        let identifier = metadata.nip05?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        latestNIP05IdentifiersByPubkey[pubkey] = identifier

        guard !identifier.isEmpty else {
            nip05TasksByPubkey.removeValue(forKey: pubkey)?.cancel()
            resolvingNIP05IdentifiersByPubkey.removeValue(forKey: pubkey)
            guard nip05Resolutions.removeValue(forKey: pubkey) != nil else { return }
            Task { await onChange() }
            return
        }
        guard nip05Resolutions[pubkey]?.identifier != identifier else { return }
        guard resolvingNIP05IdentifiersByPubkey[pubkey] != identifier else { return }

        nip05TasksByPubkey.removeValue(forKey: pubkey)?.cancel()
        resolvingNIP05IdentifiersByPubkey[pubkey] = identifier
        let resolver = nip05Resolver
        let generation = lifecycleGeneration
        nip05TasksByPubkey[pubkey] = Task(priority: .utility) { [weak self] in
            let resolution = await resolver.resolve(identifier: identifier, expectedPubkey: pubkey)
            guard !Task.isCancelled,
                  let self,
                  self.lifecycleGeneration == generation,
                  self.latestNIP05IdentifiersByPubkey[pubkey] == resolution.identifier
            else { return }
            if self.resolvingNIP05IdentifiersByPubkey[pubkey] == identifier {
                self.resolvingNIP05IdentifiersByPubkey.removeValue(forKey: pubkey)
            }
            self.nip05TasksByPubkey.removeValue(forKey: pubkey)
            self.nip05Resolutions[pubkey] = resolution
            await onChange()
        }
    }

    private func ensureProfiles(
        for event: NostrEvent,
        dependencies: NostrEventDependencies
    ) async {
        await profileDirectory?.ensureProfiles(
            pubkeys: [event.pubkey],
            relayHintsByPubkey: dependencies.profileRelayURLsByPubkey.filter {
                $0.key == event.pubkey
            },
            priority: .foreground
        )
        let backgroundPubkeys = dependencies.profilePubkeys.filter { $0 != event.pubkey }
        guard !backgroundPubkeys.isEmpty else { return }
        await profileDirectory?.ensureProfiles(
            pubkeys: backgroundPubkeys,
            relayHintsByPubkey: dependencies.profileRelayURLsByPubkey.filter {
                backgroundPubkeys.contains($0.key)
            },
            priority: .background
        )
    }

    private func profileMetadata(from event: NostrEvent) -> NostrProfileMetadata? {
        guard let data = event.content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
    }
}

private extension NostrDependencyFetchCacheSnapshot {
    func hasResolvedDependencies(for dependencies: NostrEventDependencies) -> Bool {
        dependencies.profilePubkeys.contains { profileReceivedAtByPubkey[$0] != nil } ||
            dependencies.sourceEventIDs.contains { sourceEventIDs.contains($0) }
    }
}
