import AstrenzaCore
import Foundation

struct HomeTimelineDependencyEnqueueResult: Sendable {
    let cachedProfiles: [NostrEvent]
    let didResolveCachedDependencies: Bool
    let didEnqueueSourceDependencies: Bool
}

struct HomeTimelineProfileUpdateSource: Sendable {
    typealias UpdatesProvider = @MainActor @Sendable () async -> AsyncStream<NostrProfileDirectoryUpdate>
    typealias RelayHandler = @MainActor @Sendable (_ relayURLs: [String]) async -> Void
    typealias StopHandler = @MainActor @Sendable () async -> Void

    let updates: UpdatesProvider
    let start: RelayHandler
    let updateRelayURLs: RelayHandler
    let stop: StopHandler

    init(
        updates: @escaping UpdatesProvider,
        start: @escaping RelayHandler,
        updateRelayURLs: @escaping RelayHandler,
        stop: @escaping StopHandler
    ) {
        self.updates = updates
        self.start = start
        self.updateRelayURLs = updateRelayURLs
        self.stop = stop
    }

    init(profileDirectory: NostrProfileDirectory) {
        self.init(
            updates: { await profileDirectory.updates() },
            start: { relayURLs in
                await profileDirectory.start(relayURLs: relayURLs)
            },
            updateRelayURLs: { relayURLs in
                await profileDirectory.updateRelayURLs(relayURLs)
            },
            stop: {
                await profileDirectory.stop()
            }
        )
    }
}

@MainActor
final class HomeTimelineDependencyResolutionCoordinator {
    typealias NIP05ResolutionChangeHandler = @MainActor @Sendable () async -> Void
    typealias ProfileUpdateHandler = @MainActor @Sendable (_ update: NostrProfileDirectoryUpdate) -> Void
    typealias SourcePacketInstaller = @MainActor @Sendable (_ packets: [NostrREQPacket]) async throws -> Void
    typealias SourceInstallFailureHandler = @MainActor @Sendable (_ message: String) -> Void

    private let eventIngestor: HomeTimelineEventIngestor
    private let profileDirectory: NostrProfileDirectory?
    private let nip05Resolver: any NostrNIP05Resolving
    private let syncPlanner: HomeTimelineSyncPlanner
    private let sourcePacketInstaller: SourcePacketInstaller?
    private let sourceFlushDelayNanoseconds: UInt64
    private let profileUpdateSource: HomeTimelineProfileUpdateSource?

    private var sourceQueue = NostrDependencyFetchQueue()
    private var sourceEventIDsByGroupID: [String: [String]] = [:]
    private var sourceFlushTask: Task<Void, Never>?
    private var sourceInstallTasks: [UUID: Task<Void, Never>] = [:]
    private var profileUpdateTask: Task<Void, Never>?
    private var profileUpdateSequence: UInt64 = 0
    private var resolvingNIP05IdentifiersByPubkey: [String: String] = [:]
    private var latestNIP05IdentifiersByPubkey: [String: String] = [:]
    private var nip05TasksByPubkey: [String: Task<Void, Never>] = [:]
    private var lifecycleGeneration: UInt64 = 0

    private(set) var nip05Resolutions: [String: NostrNIP05Resolution] = [:]
    private(set) var profileResolutionStates: [String: NostrProfileResolutionState] = [:]

    init(
        eventIngestor: HomeTimelineEventIngestor,
        profileDirectory: NostrProfileDirectory?,
        nip05Resolver: any NostrNIP05Resolving,
        syncPlanner: HomeTimelineSyncPlanner,
        sourcePacketInstaller: SourcePacketInstaller? = nil,
        sourceFlushDelayNanoseconds: UInt64 = 12_000_000,
        profileUpdateSource: HomeTimelineProfileUpdateSource? = nil
    ) {
        self.eventIngestor = eventIngestor
        self.profileDirectory = profileDirectory
        self.nip05Resolver = nip05Resolver
        self.syncPlanner = syncPlanner
        self.sourcePacketInstaller = sourcePacketInstaller
        self.sourceFlushDelayNanoseconds = sourceFlushDelayNanoseconds
        if let profileUpdateSource {
            self.profileUpdateSource = profileUpdateSource
        } else if let profileDirectory {
            self.profileUpdateSource = HomeTimelineProfileUpdateSource(
                profileDirectory: profileDirectory
            )
        } else {
            self.profileUpdateSource = nil
        }
    }

    var hasPendingWork: Bool {
        sourceQueue.hasPendingWork || !sourceEventIDsByGroupID.isEmpty
    }

    var pendingSourceRequestCount: Int {
        sourceEventIDsByGroupID.count
    }

    var hasScheduledSourceFlush: Bool {
        sourceFlushTask != nil
    }

    var activeSourceInstallCount: Int {
        sourceInstallTasks.count
    }

    var isObservingProfileUpdates: Bool {
        profileUpdateTask != nil
    }

    func reset() {
        lifecycleGeneration &+= 1
        profileUpdateSequence &+= 1
        profileUpdateTask?.cancel()
        profileUpdateTask = nil
        sourceFlushTask?.cancel()
        sourceFlushTask = nil
        sourceInstallTasks.values.forEach { $0.cancel() }
        sourceInstallTasks.removeAll()
        nip05TasksByPubkey.values.forEach { $0.cancel() }
        nip05TasksByPubkey.removeAll()
        resolvingNIP05IdentifiersByPubkey.removeAll()
        latestNIP05IdentifiersByPubkey.removeAll()
        nip05Resolutions.removeAll()
        profileResolutionStates.removeAll()
        sourceQueue.removeAll()
        sourceEventIDsByGroupID.removeAll()
    }

    func replaceNIP05Resolutions(_ resolutions: [String: NostrNIP05Resolution]) {
        nip05Resolutions = resolutions
    }

    @discardableResult
    func startProfileUpdates(
        relayURLs: [String],
        initialEvents: [NostrEvent] = [],
        onUpdate: @escaping ProfileUpdateHandler
    ) -> Bool {
        guard let profileUpdateSource, profileUpdateTask == nil else { return false }
        profileUpdateSequence &+= 1
        let expectedSequence = profileUpdateSequence
        let expectedLifecycleGeneration = lifecycleGeneration
        profileUpdateTask = Task { @MainActor [weak self] in
            let updates = await profileUpdateSource.updates()
            guard !Task.isCancelled,
                  self?.isCurrentProfileUpdate(
                    lifecycleGeneration: expectedLifecycleGeneration,
                    sequence: expectedSequence
                  ) == true
            else { return }

            await profileUpdateSource.start(relayURLs)
            guard !Task.isCancelled,
                  self?.isCurrentProfileUpdate(
                    lifecycleGeneration: expectedLifecycleGeneration,
                    sequence: expectedSequence
                  ) == true
            else { return }

            await self?.ensureProfiles(for: initialEvents)
            guard !Task.isCancelled,
                  self?.isCurrentProfileUpdate(
                    lifecycleGeneration: expectedLifecycleGeneration,
                    sequence: expectedSequence
                  ) == true
            else { return }

            for await update in updates {
                guard !Task.isCancelled,
                      let self,
                      isCurrentProfileUpdate(
                        lifecycleGeneration: expectedLifecycleGeneration,
                        sequence: expectedSequence
                      )
                else { break }
                profileResolutionStates.merge(update.states) { _, latest in latest }
                onUpdate(update)
            }

            guard let self,
                  isCurrentProfileUpdate(
                    lifecycleGeneration: expectedLifecycleGeneration,
                    sequence: expectedSequence
                  )
            else { return }
            profileUpdateTask = nil
        }
        return true
    }

    func updateProfileRelayURLs(_ relayURLs: [String]) async {
        await profileUpdateSource?.updateRelayURLs(relayURLs)
    }

    func stopProfileUpdates() async {
        profileUpdateSequence &+= 1
        profileUpdateTask?.cancel()
        profileUpdateTask = nil
        await profileUpdateSource?.stop()
    }

    func enqueueDependencies(
        for event: NostrEvent,
        liveMetadataEvents: [NostrEvent],
        liveNoteEventIDs: Set<String>,
        availableRelayURLs: [String],
        now: Int = Int(Date().timeIntervalSince1970)
    ) async -> HomeTimelineDependencyEnqueueResult {
        await enqueueDependencies(
            for: [event],
            liveMetadataEvents: liveMetadataEvents,
            liveNoteEventIDs: liveNoteEventIDs,
            availableRelayURLs: availableRelayURLs,
            now: now
        )
    }

    func enqueueDependencies(
        for events: [NostrEvent],
        liveMetadataEvents: [NostrEvent],
        liveNoteEventIDs: Set<String>,
        availableRelayURLs: [String],
        now: Int = Int(Date().timeIntervalSince1970)
    ) async -> HomeTimelineDependencyEnqueueResult {
        let dependencies = mergedDependencies(from: events)
        let cacheResult = await eventIngestor.dependencyCacheResult(
            dependencies: dependencies,
            liveMetadataEvents: liveMetadataEvents,
            liveNoteEventIDs: liveNoteEventIDs,
            now: now
        )

        await ensureProfiles(for: events)

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

    private func mergedDependencies(
        from events: [NostrEvent]
    ) -> NostrEventDependencies {
        var profilePubkeys: [String] = []
        var sourceEventIDs: [String] = []
        var profileRelayURLsByPubkey: [String: [String]] = [:]
        var sourceRelayURLsByEventID: [String: [String]] = [:]

        for event in events {
            let dependencies = NostrEventDependencies.extract(from: event)
            profilePubkeys.append(contentsOf: dependencies.profilePubkeys)
            sourceEventIDs.append(contentsOf: dependencies.sourceEventIDs)
            for (pubkey, relayURLs) in dependencies.profileRelayURLsByPubkey {
                profileRelayURLsByPubkey[pubkey, default: []].append(contentsOf: relayURLs)
            }
            for (eventID, relayURLs) in dependencies.sourceRelayURLsByEventID {
                sourceRelayURLsByEventID[eventID, default: []].append(contentsOf: relayURLs)
            }
        }

        return NostrEventDependencies(
            profilePubkeys: profilePubkeys,
            sourceEventIDs: sourceEventIDs,
            profileRelayURLsByPubkey: profileRelayURLsByPubkey,
            sourceRelayURLsByEventID: sourceRelayURLsByEventID
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

    @discardableResult
    func scheduleSourcePacketInstall(
        onFailure: @escaping SourceInstallFailureHandler
    ) -> Bool {
        guard sourceFlushTask == nil, sourcePacketInstaller != nil else { return false }
        let generation = lifecycleGeneration
        let delayNanoseconds = sourceFlushDelayNanoseconds
        sourceFlushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard let self, lifecycleGeneration == generation else { return }
            sourceFlushTask = nil
            _ = startSourcePacketInstall(onFailure: onFailure)
        }
        return true
    }

    @discardableResult
    func flushSourcePacketInstall(
        onFailure: @escaping SourceInstallFailureHandler
    ) -> Bool {
        sourceFlushTask?.cancel()
        sourceFlushTask = nil
        return startSourcePacketInstall(onFailure: onFailure)
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
    func completeSourceRequest(
        _ completion: NostrBackwardREQCompletion,
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> Bool {
        guard let eventIDs = sourceEventIDsByGroupID.removeValue(forKey: completion.groupID) else {
            return false
        }
        switch completion.status {
        case .completed:
            let unresolvedEventIDs = eventIDs.filter(
                sourceQueue.pendingSourceEventIDs.contains
            )
            let resolvedEventIDs = eventIDs.filter {
                !sourceQueue.pendingSourceEventIDs.contains($0)
            }
            sourceQueue.finish(
                sourceEventIDs: resolvedEventIDs,
                succeeded: true,
                now: now
            )
            sourceQueue.finish(
                sourceEventIDs: unresolvedEventIDs,
                succeeded: false,
                now: now
            )
        case .partial, .closed, .timedOut:
            let unresolvedEventIDs = eventIDs.filter(
                sourceQueue.pendingSourceEventIDs.contains
            )
            sourceQueue.finish(
                sourceEventIDs: unresolvedEventIDs,
                succeeded: false,
                now: now
            )
        }
        return true
    }

    private func startSourcePacketInstall(
        onFailure: @escaping SourceInstallFailureHandler
    ) -> Bool {
        guard let sourcePacketInstaller else { return false }
        let plan = drainSourcePacketPlan()
        guard !plan.sourcePackets.isEmpty else { return false }

        let taskID = UUID()
        let generation = lifecycleGeneration
        let packets = plan.sourcePackets
        sourceInstallTasks[taskID] = Task { @MainActor [weak self] in
            let failureMessage: String?
            do {
                try await sourcePacketInstaller(packets)
                failureMessage = nil
            } catch {
                failureMessage = error.localizedDescription
            }

            guard !Task.isCancelled,
                  let self,
                  lifecycleGeneration == generation
            else { return }
            sourceInstallTasks.removeValue(forKey: taskID)
            guard let failureMessage else { return }
            failSourceRequests(in: plan)
            onFailure(failureMessage)
        }
        return true
    }

    private func isCurrentProfileUpdate(
        lifecycleGeneration: UInt64,
        sequence: UInt64
    ) -> Bool {
        self.lifecycleGeneration == lifecycleGeneration && profileUpdateSequence == sequence
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
