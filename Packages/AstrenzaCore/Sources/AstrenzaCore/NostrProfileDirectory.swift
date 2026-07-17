import Foundation
import NostrProtocol
import NostrRelay
import NostrStoreAPI
import NostrStoreGRDB
import NostrSync

public enum NostrProfileRequestPriority: Equatable, Sendable {
    case foreground
    case background
}

public struct NostrProfileDirectoryPolicy: Equatable, Sendable {
    public let staleAfterSeconds: Int
    public let notFoundRetryAfterSeconds: Int
    public let failureRetryAfterSeconds: Int
    public let foregroundBatchDelayMilliseconds: Int
    public let backgroundBatchDelayMilliseconds: Int
    public let persistenceBatchDelayMilliseconds: Int
    public let persistenceBatchSize: Int

    public init(
        staleAfterSeconds: Int = 24 * 60 * 60,
        notFoundRetryAfterSeconds: Int = 15 * 60,
        failureRetryAfterSeconds: Int = 60,
        foregroundBatchDelayMilliseconds: Int = 12,
        backgroundBatchDelayMilliseconds: Int = 250,
        persistenceBatchDelayMilliseconds: Int = 8,
        persistenceBatchSize: Int = 32
    ) {
        self.staleAfterSeconds = max(0, staleAfterSeconds)
        self.notFoundRetryAfterSeconds = max(0, notFoundRetryAfterSeconds)
        self.failureRetryAfterSeconds = max(0, failureRetryAfterSeconds)
        self.foregroundBatchDelayMilliseconds = max(0, foregroundBatchDelayMilliseconds)
        self.backgroundBatchDelayMilliseconds = max(0, backgroundBatchDelayMilliseconds)
        self.persistenceBatchDelayMilliseconds = max(0, persistenceBatchDelayMilliseconds)
        self.persistenceBatchSize = max(1, persistenceBatchSize)
    }
}

public struct NostrProfileDirectoryUpdate: Equatable, Sendable {
    public let states: [String: NostrProfileResolutionState]
    public let metadataEvents: [NostrEvent]

    public init(
        states: [String: NostrProfileResolutionState] = [:],
        metadataEvents: [NostrEvent] = []
    ) {
        self.states = states
        self.metadataEvents = metadataEvents
    }
}

/// kind:0のcache、取得状態、batch、retryをTimelineから独立して管理します。
public actor NostrProfileDirectory {
    public nonisolated static let groupIDPrefix = "astrenza-profile-directory"

    private struct RelaySelectionKey: Hashable, Sendable {
        let relayURLs: [String]
    }

    private struct RequestGroup: Sendable {
        let pubkeys: Set<String>
        let cachedPubkeys: Set<String>
        let subscriptionID: String
        let attemptedAt: Int
        var resolvedPubkeys = Set<String>()
    }

    private struct RequestContext: Sendable {
        var relayHints: [String]
        var priority: NostrProfileRequestPriority
    }

    private struct PendingProfilePersistence: Sendable {
        let groupID: String
        let event: NostrEvent
        let source: NostrEventSourceRecord
        let fetchRecord: NostrProfileFetchRecord
        let receivedAt: Int
    }

    private let eventStore: NostrEventStore?
    private let relayRuntime: NostrRelayRuntime
    private let policy: NostrProfileDirectoryPolicy
    private var relayURLs: [String] = []
    private var states: [String: NostrProfileResolutionState] = [:]
    private var activePubkeys = Set<String>()
    private var foregroundQueue: [RelaySelectionKey: Set<String>] = [:]
    private var backgroundQueue: [RelaySelectionKey: Set<String>] = [:]
    private var cachedQueuedPubkeys = Set<String>()
    private var requestGroups: [String: RequestGroup] = [:]
    private var runtimeTask: Task<Void, Never>?
    private var foregroundFlushTask: Task<Void, Never>?
    private var backgroundFlushTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var persistenceFlushTask: Task<Void, Never>?
    private var pendingProfilePersistence: [PendingProfilePersistence] = []
    private var deferredCompletionsByGroupID: [
        String: NostrBackwardREQCompletion
    ] = [:]
    private var requestContexts: [String: RequestContext] = [:]
    private var retryAtByPubkey: [String: Int] = [:]
    private var lifecycleGeneration: UInt64 = 0
    private var continuations: [UUID: AsyncStream<NostrProfileDirectoryUpdate>.Continuation] = [:]

    public init(
        eventStore: NostrEventStore?,
        relayRuntime: NostrRelayRuntime,
        policy: NostrProfileDirectoryPolicy = NostrProfileDirectoryPolicy()
    ) {
        self.eventStore = eventStore
        self.relayRuntime = relayRuntime
        self.policy = policy
    }

    public nonisolated static func handles(subscriptionID: String) -> Bool {
        subscriptionID.hasPrefix(groupIDPrefix + "-")
    }

    public nonisolated static func handles(groupID: String) -> Bool {
        groupID.hasPrefix(groupIDPrefix + "-")
    }

    public func updates() -> AsyncStream<NostrProfileDirectoryUpdate> {
        let observerID = UUID()
        return AsyncStream { continuation in
            continuations[observerID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(observerID) }
            }
        }
    }

    public func start(relayURLs: [String]) async {
        self.relayURLs = relayURLs.dedupedPreservingOrder()
        guard runtimeTask == nil else { return }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        let stream = await relayRuntime.events()
        runtimeTask = Task { [weak self] in
            for await packet in stream {
                guard !Task.isCancelled else { break }
                await self?.handle(packet, generation: generation)
            }
            await self?.runtimePumpFinished(generation: generation)
        }
    }

    public func updateRelayURLs(_ relayURLs: [String]) {
        self.relayURLs = relayURLs.dedupedPreservingOrder()
    }

    public func stop() {
        _ = flushProfilePersistence()
        lifecycleGeneration &+= 1
        runtimeTask?.cancel()
        foregroundFlushTask?.cancel()
        backgroundFlushTask?.cancel()
        retryTask?.cancel()
        persistenceFlushTask?.cancel()
        runtimeTask = nil
        foregroundFlushTask = nil
        backgroundFlushTask = nil
        retryTask = nil
        persistenceFlushTask = nil
        foregroundQueue.removeAll()
        backgroundQueue.removeAll()
        cachedQueuedPubkeys.removeAll()
        requestGroups.removeAll()
        deferredCompletionsByGroupID.removeAll()
        activePubkeys.removeAll()
        requestContexts.removeAll()
        retryAtByPubkey.removeAll()
        states = states.mapValues { state in
            state == .fetching ? .unknown : state
        }
    }

    public func ensureProfiles(
        pubkeys: [String],
        relayHintsByPubkey: [String: [String]] = [:],
        priority: NostrProfileRequestPriority,
        now: Int = Int(Date().timeIntervalSince1970)
    ) {
        let requestedPubkeys = Set(pubkeys.filter { !$0.isEmpty })
        guard !requestedPubkeys.isEmpty else { return }
        for pubkey in requestedPubkeys {
            rememberRequestContext(
                pubkey: pubkey,
                relayHints: relayHintsByPubkey[pubkey] ?? [],
                priority: priority
            )
        }

        let cachedEvents = (try? eventStore?.latestReplaceableEvents(
            pubkeys: requestedPubkeys,
            kind: 0,
            now: now
        )) ?? []
        let cachedPubkeys = Set(cachedEvents.map(\.pubkey))
        let cachedEventByPubkey = Dictionary(
            cachedEvents.map { ($0.pubkey, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let receivedAtByPubkey = (try? eventStore?.latestReplaceableEventReceivedAtByPubkey(
            pubkeys: requestedPubkeys,
            kind: 0,
            now: now
        )) ?? [:]
        let fetchRecords = (try? eventStore?.profileFetchRecords(pubkeys: requestedPubkeys)) ?? []
        let fetchRecordByPubkey = Dictionary(uniqueKeysWithValues: fetchRecords.map { ($0.pubkey, $0) })

        var changedStates: [String: NostrProfileResolutionState] = [:]
        var cachedEventsToEmit: [NostrEvent] = []
        var failedRecords: [NostrProfileFetchRecord] = []
        for pubkey in requestedPubkeys {
            let hasCachedMetadata = cachedPubkeys.contains(pubkey)
            if hasCachedMetadata {
                if states[pubkey] != .resolved,
                   let cachedEvent = cachedEventByPubkey[pubkey] {
                    cachedEventsToEmit.append(cachedEvent)
                }
                setState(.resolved, for: pubkey, changedStates: &changedStates)
            }

            guard !activePubkeys.contains(pubkey) else { continue }
            let isFresh = receivedAtByPubkey[pubkey].map { now - $0 < policy.staleAfterSeconds } ?? false
            if isFresh {
                clearRetry(for: pubkey, removeRequestContext: true)
                continue
            }

            if let nextRetryAt = fetchRecordByPubkey[pubkey]?.nextRetryAt,
               nextRetryAt > now {
                retryAtByPubkey[pubkey] = nextRetryAt
                if !hasCachedMetadata {
                    setState(.unavailable, for: pubkey, changedStates: &changedStates)
                }
                continue
            }

            let selectedRelays = relaySelection(
                hintedRelayURLs: relayHintsByPubkey[pubkey] ?? [],
                availableRelayURLs: relayURLs
            )
            guard !selectedRelays.isEmpty else {
                if !hasCachedMetadata {
                    setState(.unavailable, for: pubkey, changedStates: &changedStates)
                }
                failedRecords.append(fetchRecord(
                    pubkey: pubkey,
                    outcome: .failed,
                    attemptedAt: now,
                    retryAfterSeconds: policy.failureRetryAfterSeconds,
                    error: "no eligible profile relays",
                    now: now
                ))
                retryAtByPubkey[pubkey] = now + policy.failureRetryAfterSeconds
                continue
            }

            retryAtByPubkey[pubkey] = nil
            activePubkeys.insert(pubkey)
            if hasCachedMetadata {
                cachedQueuedPubkeys.insert(pubkey)
            } else {
                setState(.fetching, for: pubkey, changedStates: &changedStates)
            }
            let key = RelaySelectionKey(relayURLs: selectedRelays)
            switch priority {
            case .foreground:
                foregroundQueue[key, default: []].insert(pubkey)
            case .background:
                backgroundQueue[key, default: []].insert(pubkey)
            }
        }

        try? eventStore?.saveProfileFetchRecords(failedRecords)
        emit(NostrProfileDirectoryUpdate(
            states: changedStates,
            metadataEvents: cachedEventsToEmit.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id < $1.id
            }
        ))
        scheduleFlush(priority: priority)
        scheduleRetryTask()
    }

    public func snapshot(pubkeys: Set<String>) -> [String: NostrProfileResolutionState] {
        states.filter { pubkeys.contains($0.key) }
    }

    private func scheduleFlush(priority: NostrProfileRequestPriority) {
        switch priority {
        case .foreground:
            guard foregroundFlushTask == nil, !foregroundQueue.isEmpty else { return }
            let delay = policy.foregroundBatchDelayMilliseconds
            foregroundFlushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                await self?.flush(priority: .foreground)
            }
        case .background:
            guard backgroundFlushTask == nil, !backgroundQueue.isEmpty else { return }
            let delay = policy.backgroundBatchDelayMilliseconds
            backgroundFlushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                await self?.flush(priority: .background)
            }
        }
    }

    private func flush(priority: NostrProfileRequestPriority) async {
        let queued: [RelaySelectionKey: Set<String>]
        switch priority {
        case .foreground:
            foregroundFlushTask = nil
            queued = foregroundQueue
            foregroundQueue.removeAll()
        case .background:
            backgroundFlushTask = nil
            queued = backgroundQueue
            backgroundQueue.removeAll()
        }
        guard !queued.isEmpty else { return }

        let generation = lifecycleGeneration
        for (relayKey, pubkeys) in queued {
            guard lifecycleGeneration == generation, !pubkeys.isEmpty else { return }
            let requestID = UUID().uuidString.lowercased()
            let groupID = "\(Self.groupIDPrefix)-\(requestID)"
            let subscriptionID = "\(groupID)-req"
            let packet = NostrREQPacket.backward(
                purpose: "profile-directory",
                filters: [[
                    "kinds": .ints([0]),
                    "authors": .strings(pubkeys.sorted())
                ]],
                relayURLs: relayKey.relayURLs,
                groupID: groupID,
                subscriptionID: subscriptionID
            )
            let now = Int(Date().timeIntervalSince1970)
            requestGroups[groupID] = RequestGroup(
                pubkeys: pubkeys,
                cachedPubkeys: pubkeys.intersection(cachedQueuedPubkeys),
                subscriptionID: subscriptionID,
                attemptedAt: now
            )

            do {
                try await relayRuntime.installBackward(
                    [packet],
                    mergeField: .authors,
                    priority: priority == .foreground
                        ? .visibleDependency
                        : .backgroundDependency
                )
            } catch {
                guard lifecycleGeneration == generation else { return }
                failRequestGroup(
                    groupID: groupID,
                    message: String(describing: error),
                    now: Int(Date().timeIntervalSince1970)
                )
            }
        }
    }

    private func handle(_ packet: NostrRelayRuntimePacket, generation: UInt64) {
        guard lifecycleGeneration == generation else { return }
        switch packet {
        case .event(let relayURL, let subscriptionID, let event):
            handleMetadataEvent(relayURL: relayURL, subscriptionID: subscriptionID, event: event)
        case .backwardCompleted(let completion):
            handleCompletion(completion)
        default:
            break
        }
    }

    private func handleMetadataEvent(relayURL: String, subscriptionID: String, event: NostrEvent) {
        guard event.kind == 0,
              let groupID = requestGroupID(for: subscriptionID),
              let group = requestGroups[groupID],
              group.pubkeys.contains(event.pubkey)
        else { return }

        let now = Int(Date().timeIntervalSince1970)
        let source = NostrEventSourceRecord(
            eventID: event.id,
            relayURL: relayURL,
            firstSeenAt: now,
            lastSeenAt: now
        )
        enqueueProfilePersistence(PendingProfilePersistence(
            groupID: groupID,
            event: event,
            source: source,
            fetchRecord: NostrProfileFetchRecord(
                pubkey: event.pubkey,
                outcome: .resolved,
                lastAttemptAt: group.attemptedAt,
                lastSuccessAt: now,
                updatedAt: now
            ),
            receivedAt: now
        ))
    }

    private func handleCompletion(_ completion: NostrBackwardREQCompletion) {
        guard flushProfilePersistence() else {
            deferredCompletionsByGroupID[completion.groupID] = completion
            return
        }
        completeRequestGroup(completion)
    }

    private func completeRequestGroup(
        _ completion: NostrBackwardREQCompletion
    ) {
        guard Self.handles(groupID: completion.groupID),
              let group = requestGroups.removeValue(forKey: completion.groupID)
        else { return }
        let unresolvedPubkeys = group.pubkeys.subtracting(group.resolvedPubkeys)
        guard !unresolvedPubkeys.isEmpty else { return }

        let now = Int(Date().timeIntervalSince1970)
        // 一部のrelayしかEOSEを返していない場合は「存在しない」とは確定できません。
        // partialを短いfailure retryへ戻すことで、応答しなかったrelayを後から再試行します。
        let isDefinitive = completion.status == .completed
        let outcome: NostrProfileFetchOutcome = isDefinitive ? .notFound : .failed
        let retryAfter = isDefinitive
            ? policy.notFoundRetryAfterSeconds
            : policy.failureRetryAfterSeconds
        var changedStates: [String: NostrProfileResolutionState] = [:]
        let records = unresolvedPubkeys.map { pubkey in
            activePubkeys.remove(pubkey)
            cachedQueuedPubkeys.remove(pubkey)
            setState(
                group.cachedPubkeys.contains(pubkey) ? .resolved : .unavailable,
                for: pubkey,
                changedStates: &changedStates
            )
            retryAtByPubkey[pubkey] = now + retryAfter
            return fetchRecord(
                pubkey: pubkey,
                outcome: outcome,
                attemptedAt: group.attemptedAt,
                retryAfterSeconds: retryAfter,
                error: isDefinitive ? nil : completion.status.noticeDescription,
                now: now
            )
        }
        try? eventStore?.saveProfileFetchRecords(records)
        emit(states: changedStates)
        scheduleRetryTask()
    }

    private func enqueueProfilePersistence(
        _ pending: PendingProfilePersistence
    ) {
        pendingProfilePersistence.append(pending)
        if pendingProfilePersistence.count >= policy.persistenceBatchSize {
            flushProfilePersistence()
            return
        }
        scheduleProfilePersistenceFlush()
    }

    @discardableResult
    private func flushProfilePersistence() -> Bool {
        persistenceFlushTask?.cancel()
        persistenceFlushTask = nil
        guard !pendingProfilePersistence.isEmpty else { return true }
        let pending = pendingProfilePersistence
        do {
            try eventStore?.ingestProfileResolutions(
                events: pending.map(\.event),
                eventSources: pending.map(\.source),
                fetchRecords: pending.map(\.fetchRecord),
                receivedAt: pending.map(\.receivedAt).max() ?? 0
            )
        } catch {
            scheduleProfilePersistenceFlush()
            return false
        }
        pendingProfilePersistence.removeAll(keepingCapacity: true)
        publishPersistedProfiles(pending)
        completeDeferredCompletions()
        return true
    }

    private func scheduleProfilePersistenceFlush() {
        guard persistenceFlushTask == nil,
              !pendingProfilePersistence.isEmpty
        else { return }
        let delay = max(1, policy.persistenceBatchDelayMilliseconds)
        persistenceFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.flushProfilePersistence()
        }
    }

    private func publishPersistedProfiles(
        _ pending: [PendingProfilePersistence]
    ) {
        var changedStates: [String: NostrProfileResolutionState] = [:]
        for item in pending {
            if var group = requestGroups[item.groupID] {
                group.resolvedPubkeys.insert(item.event.pubkey)
                requestGroups[item.groupID] = group
            }
            activePubkeys.remove(item.event.pubkey)
            cachedQueuedPubkeys.remove(item.event.pubkey)
            clearRetry(for: item.event.pubkey, removeRequestContext: true)
            setState(
                .resolved,
                for: item.event.pubkey,
                changedStates: &changedStates
            )
        }
        emit(NostrProfileDirectoryUpdate(
            states: changedStates,
            metadataEvents: pending.map(\.event)
        ))
        scheduleRetryTask()
    }

    private func completeDeferredCompletions() {
        let completions = Array(deferredCompletionsByGroupID.values)
        deferredCompletionsByGroupID.removeAll()
        for completion in completions {
            completeRequestGroup(completion)
        }
    }

    private func failRequestGroup(groupID: String, message: String, now: Int) {
        guard let group = requestGroups.removeValue(forKey: groupID) else { return }
        var changedStates: [String: NostrProfileResolutionState] = [:]
        let records = group.pubkeys.map { pubkey in
            activePubkeys.remove(pubkey)
            cachedQueuedPubkeys.remove(pubkey)
            setState(
                group.cachedPubkeys.contains(pubkey) ? .resolved : .unavailable,
                for: pubkey,
                changedStates: &changedStates
            )
            retryAtByPubkey[pubkey] = now + policy.failureRetryAfterSeconds
            return fetchRecord(
                pubkey: pubkey,
                outcome: .failed,
                attemptedAt: group.attemptedAt,
                retryAfterSeconds: policy.failureRetryAfterSeconds,
                error: message,
                now: now
            )
        }
        try? eventStore?.saveProfileFetchRecords(records)
        emit(states: changedStates)
        scheduleRetryTask()
    }

    private func rememberRequestContext(
        pubkey: String,
        relayHints: [String],
        priority: NostrProfileRequestPriority
    ) {
        let existing = requestContexts[pubkey]
        let mergedHints = ((existing?.relayHints ?? []) + relayHints).dedupedPreservingOrder()
        let effectivePriority: NostrProfileRequestPriority =
            existing?.priority == .foreground || priority == .foreground
            ? .foreground
            : .background
        requestContexts[pubkey] = RequestContext(
            relayHints: mergedHints,
            priority: effectivePriority
        )
    }

    private func clearRetry(for pubkey: String, removeRequestContext: Bool) {
        retryAtByPubkey[pubkey] = nil
        if removeRequestContext {
            requestContexts[pubkey] = nil
        }
    }

    private func scheduleRetryTask() {
        retryTask?.cancel()
        retryTask = nil
        guard let earliestRetryAt = retryAtByPubkey.values.min() else { return }
        let generation = lifecycleGeneration
        let now = Int(Date().timeIntervalSince1970)
        let delaySeconds = max(1, earliestRetryAt - now)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }
            await self?.runScheduledRetries(generation: generation)
        }
    }

    private func runScheduledRetries(generation: UInt64) {
        guard lifecycleGeneration == generation else { return }
        retryTask = nil
        let now = Int(Date().timeIntervalSince1970)
        let duePubkeys = retryAtByPubkey
            .filter { $0.value <= now }
            .map(\.key)
        guard !duePubkeys.isEmpty else {
            scheduleRetryTask()
            return
        }
        duePubkeys.forEach { retryAtByPubkey[$0] = nil }

        for priority in [NostrProfileRequestPriority.foreground, .background] {
            let pubkeys = duePubkeys.filter { requestContexts[$0]?.priority == priority }
            guard !pubkeys.isEmpty else { continue }
            let relayHints: [String: [String]] = Dictionary(
                uniqueKeysWithValues: pubkeys.compactMap { pubkey -> (String, [String])? in
                    guard let hints = requestContexts[pubkey]?.relayHints, !hints.isEmpty else { return nil }
                    return (pubkey, hints)
                }
            )
            ensureProfiles(
                pubkeys: pubkeys,
                relayHintsByPubkey: relayHints,
                priority: priority,
                now: now
            )
        }
        scheduleRetryTask()
    }

    private func requestGroupID(for subscriptionID: String) -> String? {
        requestGroups.first { _, group in
            subscriptionID == group.subscriptionID ||
                subscriptionID.hasPrefix(group.subscriptionID + "-chunk")
        }?.key
    }

    private func setState(
        _ state: NostrProfileResolutionState,
        for pubkey: String,
        changedStates: inout [String: NostrProfileResolutionState]
    ) {
        guard states[pubkey] != state else { return }
        states[pubkey] = state
        changedStates[pubkey] = state
    }

    private func fetchRecord(
        pubkey: String,
        outcome: NostrProfileFetchOutcome,
        attemptedAt: Int,
        retryAfterSeconds: Int,
        error: String?,
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> NostrProfileFetchRecord {
        NostrProfileFetchRecord(
            pubkey: pubkey,
            outcome: outcome,
            lastAttemptAt: attemptedAt,
            nextRetryAt: now + retryAfterSeconds,
            lastError: error,
            updatedAt: now
        )
    }

    private func relaySelection(
        hintedRelayURLs: [String],
        availableRelayURLs: [String]
    ) -> [String] {
        hintedRelayURLs.isEmpty ? availableRelayURLs : hintedRelayURLs
    }

    private func emit(states: [String: NostrProfileResolutionState]) {
        guard !states.isEmpty else { return }
        emit(NostrProfileDirectoryUpdate(states: states))
    }

    private func emit(_ update: NostrProfileDirectoryUpdate) {
        guard !update.states.isEmpty || !update.metadataEvents.isEmpty else { return }
        for continuation in continuations.values {
            continuation.yield(update)
        }
    }

    private func removeContinuation(_ observerID: UUID) {
        continuations[observerID] = nil
    }

    private func runtimePumpFinished(generation: UInt64) {
        guard lifecycleGeneration == generation else { return }
        _ = flushProfilePersistence()
        runtimeTask = nil
    }
}

private extension Array where Element == String {
    func dedupedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private extension NostrBackwardREQCompletionStatus {
    var noticeDescription: String {
        switch self {
        case .completed:
            "completed"
        case .partial:
            "partial"
        case .closed:
            "closed"
        case .timedOut:
            "timeout"
        }
    }
}
