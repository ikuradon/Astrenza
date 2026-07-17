import Foundation
import NostrCryptoAPI
import NostrCryptoSecp256k1
import NostrProtocol
import NostrRelay
import NostrStoreAPI

public actor NostrRelayRuntime {
    public typealias TransportFactory = @Sendable (String) -> any NostrRelayTransport
    public typealias RetryJitterSource = @Sendable () -> Double

    private let transportFactory: TransportFactory
    private let eventValidator: any NostrEventValidating
    private let autoReceive: Bool
    private let retryPolicy: NostrRelayRuntimeRetryPolicy
    private let retryJitterSource: RetryJitterSource
    private let reconnectOverlapSeconds: Int
    private let heartbeatPolicy: NostrRelayRuntimeHeartbeatPolicy
    private let backwardPolicy: NostrRelayRuntimeBackwardPolicy
    private let relayInformationFetcher: (any NostrRelayInformationFetching)?
    private let workScheduler: NostrRelayWorkScheduler
    private var sessions: [String: NostrRelaySession] = [:]
    private var relayURLs: [String] = []
    private var activeForwardPackets: [String: NostrREQPacket] = [:]
    private var sessionPumpTasks: [String: Task<Void, Never>] = [:]
    private var receiveLoopTasks: [String: Task<Void, Never>] = [:]
    private var heartbeatLoopTasks: [String: Task<Void, Never>] = [:]
    private var heartbeatMissCounts: [String: Int] = [:]
    private var forwardClosedRetryTasks: [String: Task<Void, Never>] = [:]
    private var forwardClosedRetryAttempts: [String: Int] = [:]
    private var forwardWorkTickets: [String: NostrRelayWorkTicket] = [:]
    private var forwardActivationTasks: [String: Task<Void, Never>] = [:]
    private var backwardTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var backwardProgressBySubscriptionKey: [String: BackwardSubscriptionProgress] = [:]
    private var backwardSubscriptionKeysByGroupID: [String: Set<String>] = [:]
    private var pendingFetchesBySubscriptionKey: [String: PendingRelayFetch] = [:]
    private var bootstrapRelayURLsByScopeID: [UUID: Set<String>] = [:]
    private var completedBootstrapScopeIDs: Set<UUID> = []
    private var relayDemands = NostrRelayDemandRegistry()
    private var forwardReconnectTracker = NostrForwardReconnectTracker()
    private var relayInformationTasks: [String: Task<Void, Never>] = [:]
    private var nextBackwardProgressGeneration: UInt64 = 0
    private var trafficAccountID: String?
    private var trafficPolicy = NostrSyncPolicy.default()
    private var continuations: [UUID: AsyncStream<NostrRelayRuntimePacket>.Continuation] = [:]

    public init(
        transportFactory: @escaping TransportFactory,
        eventValidator: any NostrEventValidating = NostrEventValidator(),
        autoReceive: Bool = true,
        retryPolicy: NostrRelayRuntimeRetryPolicy = NostrRelayRuntimeRetryPolicy(),
        retryJitterSource: @escaping RetryJitterSource = {
            Double.random(in: 0...1)
        },
        reconnectOverlapSeconds: Int = 10,
        heartbeatPolicy: NostrRelayRuntimeHeartbeatPolicy = NostrRelayRuntimeHeartbeatPolicy(),
        backwardPolicy: NostrRelayRuntimeBackwardPolicy = NostrRelayRuntimeBackwardPolicy(),
        relayInformationFetcher: (any NostrRelayInformationFetching)? = nil,
        workSchedulerPolicy: NostrRelayWorkSchedulerPolicy = NostrRelayWorkSchedulerPolicy()
    ) {
        self.transportFactory = transportFactory
        self.eventValidator = eventValidator
        self.autoReceive = autoReceive
        self.retryPolicy = retryPolicy
        self.retryJitterSource = retryJitterSource
        self.reconnectOverlapSeconds = max(0, reconnectOverlapSeconds)
        self.heartbeatPolicy = heartbeatPolicy
        self.backwardPolicy = backwardPolicy
        self.relayInformationFetcher = relayInformationFetcher
        workScheduler = NostrRelayWorkScheduler(policy: workSchedulerPolicy)
    }

    public func events() -> AsyncStream<NostrRelayRuntimePacket> {
        let observerID = UUID()
        return AsyncStream { continuation in
            continuations[observerID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(observerID: observerID)
                }
            }
        }
    }

    public func defaultRelayURLs() -> [String] {
        relayURLs
    }

    public func temporaryRelayURLs() -> [String] {
        sessions.keys.filter { relayURL in
            guard let identity = NostrRelayURL(relayURL) else { return false }
            return !relayDemands.contains(.persistentDefault, for: identity)
        }.sorted()
    }

    public func activeForwardSubscriptionIDs() -> [String] {
        activeForwardPackets.keys.sorted()
    }

    public func activeSubscriptionIDs(relayURL: String) async -> [String] {
        await sessions[relayURL]?.activeSubscriptionIDs() ?? []
    }

    public func connectionState(relayURL: String) async -> NostrRelayConnectionState {
        await sessions[relayURL]?.state() ?? .initialized
    }

    public func relayWorkSnapshot(relayURL: String) async -> NostrRelayWorkSnapshot? {
        guard let identity = NostrRelayURL(relayURL) else { return nil }
        return await workScheduler.snapshot(for: identity)
    }

    public func applyRelayInformation(
        _ information: NostrRelayInformationDocument,
        relayURL: String
    ) async {
        guard let identity = NostrRelayURL(relayURL) else { return }
        await workScheduler.setPublishedMaxSubscriptions(
            information.limitation?.maxSubscriptions,
            for: identity
        )
    }

    public func publish(
        event: NostrEvent,
        relayURLs: [String],
        timeoutNanoseconds: UInt64 = 7_000_000_000
    ) async -> [NostrOutboxRelayPublishResult] {
        let destinations = NostrRelayURL.normalizedStrings(relayURLs)
        return await withTaskGroup(of: NostrOutboxRelayPublishResult.self) { group in
            for relayURL in destinations {
                group.addTask {
                    await self.publish(
                        event: event,
                        relayURL: relayURL,
                        timeoutNanoseconds: timeoutNanoseconds
                    )
                }
            }

            var results: [NostrOutboxRelayPublishResult] = []
            results.reserveCapacity(destinations.count)
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.relayURL < $1.relayURL }
        }
    }

    public func fetch(
        relayURL: String,
        request: NostrRelayRequest
    ) async throws -> [NostrEvent] {
        guard let relayIdentity = NostrRelayURL(relayURL) else {
            throw NostrRelayClientError.invalidRelayURL(relayURL)
        }
        try Task.checkCancellation()

        let fetchID = UUID()
        let subscriptionID = "af-" + fetchID.uuidString.replacingOccurrences(of: "-", with: "")
        let packet = NostrREQPacket.backward(
            purpose: request.subscriptionID,
            filters: request.filters,
            relayURLs: [relayIdentity.rawValue],
            groupID: "astrenza-fetch-\(fetchID.uuidString)",
            subscriptionID: subscriptionID
        )
        let key = backwardTimeoutKey(
            relayURL: relayIdentity.rawValue,
            subscriptionID: subscriptionID
        )
        let channel = AsyncThrowingStream<[NostrEvent], any Error>.makeStream()
        pendingFetchesBySubscriptionKey[key] = PendingRelayFetch(
            relayURL: relayIdentity.rawValue,
            subscriptionID: subscriptionID,
            continuation: channel.continuation
        )

        return try await withTaskCancellationHandler {
            do {
                try await installBackward(
                    [packet],
                    mergeField: fetchMergeField(for: request),
                    chunkPolicy: NostrREQChunkPolicy(
                        maxIDsPerFilter: .max,
                        maxAuthorsPerFilter: .max,
                        maxFiltersPerRequest: .max
                    ),
                    priority: fetchWorkPriority(for: request)
                )
                try Task.checkCancellation()
                for try await events in channel.stream {
                    return events
                }
                throw NostrRelayRuntimeError.connectionUnavailable(
                    relayURL: relayIdentity.rawValue
                )
            } catch {
                let terminalError: any Error = Task.isCancelled
                    ? CancellationError()
                    : error
                await cancelFetch(
                    relayURL: relayIdentity.rawValue,
                    subscriptionID: subscriptionID,
                    error: terminalError
                )
                throw terminalError
            }
        } onCancel: {
            Task {
                await self.cancelFetch(
                    relayURL: relayIdentity.rawValue,
                    subscriptionID: subscriptionID,
                    error: CancellationError()
                )
            }
        }
    }

    public func setTrafficContext(accountID: String?, policy: NostrSyncPolicy) async {
        trafficAccountID = accountID
        trafficPolicy = policy
        for session in sessions.values {
            await session.configureTraffic(accountID: accountID, policy: policy)
        }
    }

    public func setDefaultRelays(_ newRelayURLs: [String]) async throws {
        let normalizedRelays = NostrRelayURL.normalizedStrings(newRelayURLs)
        let previousRelayURLs = Set(relayURLs)
        let removedRelays = Set(relayURLs).subtracting(normalizedRelays)
        let addedRelays = normalizedRelays.filter { !previousRelayURLs.contains($0) }

        relayDemands.release(.persistentDefault, from: relayIdentities(removedRelays))
        relayDemands.acquire(.persistentDefault, for: relayIdentities(addedRelays))
        relayURLs = normalizedRelays
        await releaseCompletedBootstrapScopes()

        for relayURL in removedRelays {
            forwardReconnectTracker.removeRelay(relayURL)
            guard let identity = NostrRelayURL(relayURL),
                  !relayDemands.contains(.persistentDefault, for: identity)
            else { continue }

            heartbeatLoopTasks[relayURL]?.cancel()
            heartbeatLoopTasks[relayURL] = nil
            heartbeatMissCounts[relayURL] = nil
            cancelForwardClosedRetries(relayURL: relayURL)

            let forwardSubscriptionIDs = activeForwardPackets.values
                .filter { $0.relayURLs.isEmpty || canonicalRelayURLs($0.relayURLs).contains(relayURL) }
                .map(\.subscriptionID)
            for subscriptionID in forwardSubscriptionIDs {
                if let session = sessions[relayURL] {
                    try? await session.close(subscriptionID: subscriptionID)
                }
                await releaseForwardWorkTicket(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID
                )
            }
            await releaseRelaySessionIfUnneeded(relayURL)
        }

        for relayURL in addedRelays {
            scheduleRelayInformationFetch(relayURL: relayURL)
            let session: NostrRelaySession
            if let existingSession = sessions[relayURL] {
                session = existingSession
            } else {
                let newSession = NostrRelaySession(
                    relayURL: relayURL,
                    transport: transportFactory(relayURL),
                    eventValidator: eventValidator
                )
                await newSession.configureTraffic(accountID: trafficAccountID, policy: trafficPolicy)
                sessions[relayURL] = newSession
                await startPump(for: newSession, relayURL: relayURL)
                session = newSession

                do {
                    try await session.connect()
                } catch {
                    guard autoReceive else {
                        sessionPumpTasks[relayURL]?.cancel()
                        sessionPumpTasks[relayURL] = nil
                        sessions[relayURL] = nil
                        await session.terminate()
                        throw error
                    }
                }
            }
            if autoReceive {
                if receiveLoopTasks[relayURL] == nil {
                    startReceiveLoop(for: session, relayURL: relayURL)
                }
                startHeartbeatLoop(for: session, relayURL: relayURL)
            }

            for packet in activeForwardPackets.values
            where packet.relayURLs.isEmpty || canonicalRelayURLs(packet.relayURLs).contains(relayURL) {
                do {
                    try await installOrQueueForward(
                        packet,
                        relayURL: relayURL,
                        session: session
                    )
                } catch {
                    await releaseForwardWorkTicket(
                        relayURL: relayURL,
                        subscriptionID: packet.subscriptionID
                    )
                    guard autoReceive else { throw error }
                    scheduleForwardRetryAfterClosed(
                        relayURL: relayURL,
                        subscriptionID: packet.subscriptionID
                    )
                }
            }
        }
    }

    public func installForward(_ packet: NostrREQPacket) async throws {
        let forwardPacket = normalizedForwardPacket(packet)
        let installPackets = NostrREQScheduler.forwardChunks(forwardPacket)
        try await replaceForwardPackets(installPackets) { $0.groupID == forwardPacket.groupID }
    }

    public func installForward(
        _ packets: [NostrREQPacket],
        replacingGroupIDsWithPrefix groupIDPrefix: String
    ) async throws {
        let installPackets = packets
            .map(normalizedForwardPacket)
            .flatMap { NostrREQScheduler.forwardChunks($0) }
        try await replaceForwardPackets(installPackets) { $0.groupID.hasPrefix(groupIDPrefix) }
    }

    private func normalizedForwardPacket(_ packet: NostrREQPacket) -> NostrREQPacket {
        packet.strategy == .forward ? packet : NostrREQPacket.forward(
            subscriptionID: packet.subscriptionID,
            filters: packet.filters,
            relayURLs: packet.relayURLs
        )
    }

    private func replaceForwardPackets(
        _ installPackets: [NostrREQPacket],
        replacing shouldReplace: (NostrREQPacket) -> Bool
    ) async throws {
        let previousPackets = activeForwardPackets.values.filter(shouldReplace)
        forwardReconnectTracker.reset(subscriptionIDs: Set(
            previousPackets.map(\.subscriptionID)
        ))
        let installKeys = Set(installPackets.flatMap { packet in
            forwardRelayURLs(for: packet).map { relayURL in
                forwardClosedRetryKey(
                    relayURL: relayURL,
                    subscriptionID: packet.subscriptionID
                )
            }
        })
        activeForwardPackets = activeForwardPackets.filter { !shouldReplace($0.value) }
        for packet in installPackets {
            activeForwardPackets[packet.subscriptionID] = packet
        }

        for packet in previousPackets {
            let targetRelays = forwardRelayURLs(for: packet)
            for relayURL in targetRelays where !installKeys.contains(forwardClosedRetryKey(
                relayURL: relayURL,
                subscriptionID: packet.subscriptionID
            )) {
                cancelForwardClosedRetry(relayURL: relayURL, subscriptionID: packet.subscriptionID)
                if let session = sessions[relayURL] {
                    try? await session.close(subscriptionID: packet.subscriptionID)
                }
                await releaseForwardWorkTicket(
                    relayURL: relayURL,
                    subscriptionID: packet.subscriptionID
                )
            }
        }

        for packet in installPackets {
            let targetRelays = forwardRelayURLs(for: packet)
            for relayURL in targetRelays {
                guard let session = sessions[relayURL] else { continue }
                do {
                    try await installOrQueueForward(
                        packet,
                        relayURL: relayURL,
                        session: session
                    )
                    cancelForwardClosedRetry(relayURL: relayURL, subscriptionID: packet.subscriptionID)
                } catch {
                    await releaseForwardWorkTicket(
                        relayURL: relayURL,
                        subscriptionID: packet.subscriptionID
                    )
                    guard autoReceive else { throw error }
                    scheduleForwardRetryAfterClosed(
                        relayURL: relayURL,
                        subscriptionID: packet.subscriptionID
                    )
                }
            }
        }
    }

    public func installBackward(
        _ packets: [NostrREQPacket],
        mergeField: NostrREQMergeField,
        chunkPolicy: NostrREQChunkPolicy = NostrREQChunkPolicy(),
        priority: NostrRelayWorkPriority? = nil
    ) async throws {
        let backwardPackets = packets.map { packet in
            packet.strategy == .backward ? packet : NostrREQPacket.backward(
                purpose: packet.groupID,
                filters: packet.filters,
                relayURLs: packet.relayURLs,
                groupID: packet.groupID,
                subscriptionID: packet.subscriptionID
            )
        }
        let scheduledPackets = NostrREQScheduler.scheduledBatches(
            backwardPackets,
            mergeField: mergeField
        ).flatMap { batch in
            let logicalGroupIDs = batch.logicalPackets.map(\.groupID).dedupedPreservingOrder()
            return NostrREQScheduler.chunk(
                batch.packet,
                mergeField: mergeField,
                policy: chunkPolicy
            ).map { packet in
                BackwardScheduledPacket(packet: packet, logicalGroupIDs: logicalGroupIDs)
            }
        }
        guard !scheduledPackets.isEmpty else { return }
        let installationRelayURLs = scheduledPackets
            .flatMap { canonicalRelayURLs(for: $0.packet) }
            .dedupedPreservingOrder()
        let installationDemand = NostrRelayDemand.backwardInstallation(UUID())
        relayDemands.acquire(installationDemand, for: relayIdentities(installationRelayURLs))

        do {
            await prepareDemandRelaySessions(installationRelayURLs)
            try await installScheduledBackward(
                scheduledPackets,
                priorityOverride: priority
            )
        } catch {
            await releaseRelayDemand(installationDemand, from: installationRelayURLs)
            throw error
        }
        await releaseRelayDemand(installationDemand, from: installationRelayURLs)
    }

    private func installScheduledBackward(
        _ scheduledPackets: [BackwardScheduledPacket],
        priorityOverride: NostrRelayWorkPriority?
    ) async throws {
        let unavailableGroupIDs = scheduledPackets
            .filter { scheduledPacket in
                eligibleRelayURLs(for: scheduledPacket.packet).isEmpty
            }
            .flatMap(\.logicalGroupIDs)
            .dedupedPreservingOrder()
        guard unavailableGroupIDs.isEmpty else {
            throw NostrRelayRuntimeError.noEligibleRelays(groupIDs: unavailableGroupIDs)
        }

        var installTargets: [BackwardInstallTarget] = []
        for scheduledPacket in scheduledPackets {
            let packet = scheduledPacket.packet
            let targetRelays = eligibleRelayURLs(for: packet)
            for relayURL in targetRelays {
                guard let session = sessions[relayURL],
                      let identity = NostrRelayURL(relayURL)
                else { continue }
                let workTicket = await workScheduler.enqueue(
                    relayURL: identity,
                    subscriptionID: packet.subscriptionID,
                    priority: priorityOverride ?? backwardWorkPriority(for: packet)
                )
                let registration = registerBackwardSubscription(
                    relayURL: relayURL,
                    packet: packet,
                    logicalGroupIDs: scheduledPacket.logicalGroupIDs,
                    workTicket: workTicket
                )
                if let replacedWorkTicket = registration.replacedWorkTicket {
                    await workScheduler.release(replacedWorkTicket)
                }
                installTargets.append(BackwardInstallTarget(
                    relayURL: relayURL,
                    packet: packet,
                    session: session,
                    generation: registration.generation,
                    workTicket: workTicket
                ))
            }
        }

        var successfullyInstalledTargets: [BackwardInstallTarget] = []
        var firstInstallError: (any Error)?
        for target in installTargets {
            do {
                try await workScheduler.waitUntilActiveWithPolicyTimeout(target.workTicket)
                try await target.session.install(target.packet)
            } catch {
                guard autoReceive else {
                    await rollbackBackwardInstallTargets(
                        installTargets,
                        successfullyInstalledTargets: successfullyInstalledTargets
                    )
                    throw error
                }
                firstInstallError = firstInstallError ?? error
                cancelBackwardTimeout(
                    relayURL: target.relayURL,
                    subscriptionID: target.packet.subscriptionID
                )
                let didRollback = rollbackBackwardSubscription(
                    relayURL: target.relayURL,
                    subscriptionID: target.packet.subscriptionID,
                    generation: target.generation
                )
                if didRollback {
                    await workScheduler.release(target.workTicket)
                }
                continue
            }
            successfullyInstalledTargets.append(target)
            if autoReceive, receiveLoopTasks[target.relayURL] == nil {
                startReceiveLoop(for: target.session, relayURL: target.relayURL)
            }
            if hasPendingBackwardProgress(relayURL: target.relayURL, subscriptionID: target.packet.subscriptionID) {
                scheduleBackwardIdleTimeout(
                    relayURL: target.relayURL,
                    subscriptionID: target.packet.subscriptionID
                )
            }
        }

        let installedSubscriptionIDs = Set(successfullyInstalledTargets.map(\.packet.subscriptionID))
        let missingSubscriptionIDs = Set(scheduledPackets.map(\.packet.subscriptionID))
            .subtracting(installedSubscriptionIDs)
        guard missingSubscriptionIDs.isEmpty else {
            await rollbackBackwardInstallTargets(
                installTargets,
                successfullyInstalledTargets: successfullyInstalledTargets
            )
            if let firstInstallError {
                throw firstInstallError
            }
            throw NostrRelayRuntimeError.noEligibleRelays(
                groupIDs: scheduledPackets.flatMap(\.logicalGroupIDs).dedupedPreservingOrder()
            )
        }
    }

    private func rollbackBackwardInstallTargets(
        _ installTargets: [BackwardInstallTarget],
        successfullyInstalledTargets: [BackwardInstallTarget]
    ) async {
        let installedKeys = Set(successfullyInstalledTargets.map { target in
            backwardTimeoutKey(
                relayURL: target.relayURL,
                subscriptionID: target.packet.subscriptionID
            )
        })
        for target in installTargets {
            cancelBackwardTimeout(
                relayURL: target.relayURL,
                subscriptionID: target.packet.subscriptionID
            )
            let didRollback = rollbackBackwardSubscription(
                relayURL: target.relayURL,
                subscriptionID: target.packet.subscriptionID,
                generation: target.generation
            )
            if didRollback {
                await workScheduler.release(target.workTicket)
            }
            let key = backwardTimeoutKey(
                relayURL: target.relayURL,
                subscriptionID: target.packet.subscriptionID
            )
            if didRollback, installedKeys.contains(key) {
                try? await target.session.close(subscriptionID: target.packet.subscriptionID)
            }
        }
    }

    private func eligibleRelayURLs(for packet: NostrREQPacket) -> [String] {
        let candidates = canonicalRelayURLs(for: packet)
        return candidates.filter { sessions[$0] != nil }
    }

    public func sendHeartbeat(relayURL: String) async throws {
        let packet = NostrBackwardREQBuilder.heartbeat(relayURLs: [relayURL])
        try await installBackward([packet], mergeField: .ids)
    }

    public func receiveNext(relayURL: String) async throws {
        try await sessions[relayURL]?.receiveNext()
    }

    public func terminate() async {
        let sessionsToTerminate = Array(sessions.values)
        for task in sessionPumpTasks.values {
            task.cancel()
        }
        for task in receiveLoopTasks.values {
            task.cancel()
        }
        for task in heartbeatLoopTasks.values {
            task.cancel()
        }
        for task in forwardClosedRetryTasks.values {
            task.cancel()
        }
        for task in forwardActivationTasks.values {
            task.cancel()
        }
        for task in relayInformationTasks.values {
            task.cancel()
        }
        for task in backwardTimeoutTasks.values {
            task.cancel()
        }
        sessionPumpTasks = [:]
        receiveLoopTasks = [:]
        heartbeatLoopTasks = [:]
        heartbeatMissCounts = [:]
        forwardClosedRetryTasks = [:]
        forwardClosedRetryAttempts = [:]
        forwardWorkTickets = [:]
        forwardActivationTasks = [:]
        relayInformationTasks = [:]
        backwardTimeoutTasks = [:]
        backwardProgressBySubscriptionKey = [:]
        backwardSubscriptionKeysByGroupID = [:]
        finishAllPendingFetches(with: CancellationError())
        bootstrapRelayURLsByScopeID = [:]
        completedBootstrapScopeIDs = []
        relayDemands.removeAll()
        sessions = [:]
        relayURLs = []
        activeForwardPackets = [:]
        forwardReconnectTracker.removeAll()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations = [:]
        await workScheduler.cancelAll()
        for session in sessionsToTerminate {
            await session.terminate()
        }
    }

    private func startPump(for session: NostrRelaySession, relayURL: String) async {
        sessionPumpTasks[relayURL]?.cancel()
        let stream = await session.events()
        sessionPumpTasks[relayURL] = Task {
            for await packet in stream {
                await self.handleSessionPacket(packet)
            }
        }
    }

    private func handleSessionPacket(_ packet: NostrRelayRuntimePacket) async {
        switch packet {
        case .event(let relayURL, let subscriptionID, let event):
            if let forwardPacket = activeForwardPackets[subscriptionID],
               forwardPacket.relayURLs.isEmpty ||
                canonicalRelayURLs(forwardPacket.relayURLs).contains(relayURL) {
                forwardReconnectTracker.record(
                    event: event,
                    relayURL: relayURL,
                    packet: forwardPacket
                )
            }
            appendPendingFetchEvent(
                event,
                relayURL: relayURL,
                subscriptionID: subscriptionID
            )
            if hasPendingBackwardProgress(relayURL: relayURL, subscriptionID: subscriptionID) {
                incrementBackwardEventCount(relayURL: relayURL, subscriptionID: subscriptionID)
                scheduleBackwardIdleTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            }
        case .eose(let relayURL, let subscriptionID):
            if activeForwardPackets[subscriptionID] != nil {
                forwardReconnectTracker.reachedEOSE(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID
                )
                cancelForwardClosedRetry(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID
                )
            }
            finishPendingFetch(
                relayURL: relayURL,
                subscriptionID: subscriptionID
            )
            cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .eose)
        case .closed(let relayURL, let subscriptionID, let message):
            failPendingFetch(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                error: relayFetchError(forClosedMessage: message)
            )
            let wasBackwardSubscription = hasBackwardProgress(relayURL: relayURL, subscriptionID: subscriptionID)
            cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .closed)
            if !wasBackwardSubscription {
                await releaseForwardWorkTicket(
                    relayURL: relayURL,
                    subscriptionID: subscriptionID
                )
                if NostrRelayClosedDisposition(message: message) == .retryAfterDelay {
                    scheduleForwardRetryAfterClosed(relayURL: relayURL, subscriptionID: subscriptionID)
                }
            }
        case .timeout(let relayURL, let subscriptionID, _):
            failPendingFetch(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                error: NostrRelayClientError.timeout
            )
            cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .timeout)
        case .auth(let relayURL, let challenge):
            await failPendingFetches(
                relayURL: relayURL,
                error: NostrRelayClientError.authRequired(challenge: challenge)
            )
        case .stateChanged, .traffic, .requestStarted, .requestInstalled, .requestEnded,
             .notice, .backwardCompleted:
            break
        }

        emit(packet)
    }

    private func startReceiveLoop(for session: NostrRelaySession, relayURL: String) {
        receiveLoopTasks[relayURL]?.cancel()
        let retryPolicy = retryPolicy
        let retryJitterSource = retryJitterSource
        receiveLoopTasks[relayURL] = Task {
            var retryAttempt = 0
            while !Task.isCancelled {
                do {
                    try Task.checkCancellation()
                    try await session.receiveNext()
                    retryAttempt = 0
                } catch is CancellationError {
                    break
                } catch {
                    guard !Task.isCancelled else { break }
                    retryAttempt += 1
                    let failureMessage = String(describing: error)
                    if retryAttempt > retryPolicy.maxAttempts {
                        await session.markWaitingForRetry(
                            message: "relay receive failed after \(retryAttempt) attempt(s): \(failureMessage)"
                        )
                        let recoveryDelay = retryPolicy.recoveryDelayNanoseconds(
                            forAttempt: retryAttempt,
                            jitterUnit: retryJitterSource()
                        )
                        await session.markSuspended(
                            message: "reconnect retry budget exhausted; recovery scheduled in \(Self.milliseconds(recoveryDelay)) ms"
                        )
                        do {
                            try await Task.sleep(nanoseconds: recoveryDelay)
                        } catch {
                            break
                        }
                        retryAttempt = 0
                    } else {
                        let delay = retryPolicy.delayNanoseconds(
                            forAttempt: retryAttempt,
                            jitterUnit: retryJitterSource()
                        )
                        await session.markWaitingForRetry(
                            message: "reconnect attempt \(retryAttempt)/\(retryPolicy.maxAttempts) scheduled in \(Self.milliseconds(delay)) ms: \(failureMessage)"
                        )
                        if delay > 0 {
                            do {
                                try await Task.sleep(nanoseconds: delay)
                            } catch {
                                break
                            }
                        }
                    }
                    guard !Task.isCancelled else { break }

                    do {
                        let replacements = self.prepareForwardReconnectPackets(
                            relayURL: relayURL
                        )
                        try await session.reconnectRestoringSubscriptions(
                            replacingPackets: replacements
                        )
                    } catch {
                        await session.markWaitingForRetry(
                            message: "reconnect failed: \(String(describing: error))"
                        )
                    }
                }
            }
        }
    }

    private func startHeartbeatLoop(for session: NostrRelaySession, relayURL: String) {
        heartbeatLoopTasks[relayURL]?.cancel()
        let policy = heartbeatPolicy
        guard policy.isEnabled else { return }
        heartbeatLoopTasks[relayURL] = Task {
            if policy.initialDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: policy.initialDelayNanoseconds)
            }

            while !Task.isCancelled {
                do {
                    try await self.sendHeartbeat(relayURL: relayURL)
                } catch {
                    await session.markWaitingForRetry(message: "heartbeat failed: \(String(describing: error))")
                }

                try? await Task.sleep(nanoseconds: policy.intervalNanoseconds)
            }
        }
    }

    private func emit(_ packet: NostrRelayRuntimePacket) {
        for continuation in continuations.values {
            continuation.yield(packet)
        }
    }

    private func removeContinuation(observerID: UUID) {
        continuations[observerID] = nil
    }

    private func scheduleForwardRetryAfterClosed(relayURL: String, subscriptionID: String) {
        guard activeForwardPackets[subscriptionID] != nil else { return }
        let key = forwardClosedRetryKey(relayURL: relayURL, subscriptionID: subscriptionID)
        forwardClosedRetryTasks[key]?.cancel()
        let attempt = (forwardClosedRetryAttempts[key] ?? 0) + 1
        forwardClosedRetryAttempts[key] = attempt
        let delay = max(
            retryPolicy.delayNanoseconds(
                forAttempt: attempt,
                jitterUnit: retryJitterSource()
            ),
            10_000_000
        )
        emit(.notice(
            relayURL: relayURL,
            message: "forward REQ retry attempt \(attempt) scheduled in \(Self.milliseconds(delay)) ms for \(subscriptionID)"
        ))
        forwardClosedRetryTasks[key] = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.retryForwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID)
        }
    }

    private func retryForwardSubscription(relayURL: String, subscriptionID: String) async {
        let key = forwardClosedRetryKey(relayURL: relayURL, subscriptionID: subscriptionID)
        forwardClosedRetryTasks[key] = nil
        guard let packet = activeForwardPackets[subscriptionID],
              packet.relayURLs.isEmpty || canonicalRelayURLs(packet.relayURLs).contains(relayURL),
              let session = sessions[relayURL]
        else { return }
        do {
            let reconnectPacket = prepareForwardReconnectPackets(
                relayURL: relayURL,
                packets: [packet]
            )[subscriptionID] ?? packet
            try await installOrQueueForward(
                packet,
                relayURL: relayURL,
                session: session,
                installationPacket: reconnectPacket
            )
            cancelForwardClosedRetry(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                resetAttempts: false
            )
        } catch {
            await releaseForwardWorkTicket(
                relayURL: relayURL,
                subscriptionID: subscriptionID
            )
            await session.markWaitingForRetry(message: "forward REQ retry failed: \(String(describing: error))")
            scheduleForwardRetryAfterClosed(relayURL: relayURL, subscriptionID: subscriptionID)
        }
    }

    private func cancelForwardClosedRetry(
        relayURL: String,
        subscriptionID: String,
        resetAttempts: Bool = true
    ) {
        let key = forwardClosedRetryKey(relayURL: relayURL, subscriptionID: subscriptionID)
        forwardClosedRetryTasks[key]?.cancel()
        forwardClosedRetryTasks[key] = nil
        if resetAttempts {
            forwardClosedRetryAttempts[key] = nil
        }
    }

    private func cancelForwardClosedRetries(relayURL: String) {
        let prefix = relayURL + "\n"
        let keys = Set(forwardClosedRetryTasks.keys)
            .union(forwardClosedRetryAttempts.keys)
            .filter { $0.hasPrefix(prefix) }
        for key in keys {
            forwardClosedRetryTasks[key]?.cancel()
            forwardClosedRetryTasks[key] = nil
            forwardClosedRetryAttempts[key] = nil
        }
    }

    private func forwardClosedRetryKey(relayURL: String, subscriptionID: String) -> String {
        relayURL + "\n" + subscriptionID
    }

    private func scheduleBackwardIdleTimeout(relayURL: String, subscriptionID: String) {
        guard backwardPolicy.isEnabled else { return }
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        backwardTimeoutTasks[key]?.cancel()
        let timeoutNanoseconds = backwardPolicy.idleTimeoutNanoseconds
        backwardTimeoutTasks[key] = Task {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            await self.closeBackwardSubscriptionAfterIdleTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
        }
    }

    private func closeBackwardSubscriptionAfterIdleTimeout(relayURL: String, subscriptionID: String) async {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        backwardTimeoutTasks[key] = nil
        do {
            try await sessions[relayURL]?.close(
                subscriptionID: subscriptionID,
                requestEndReason: nil
            )
        } catch {
            await sessions[relayURL]?.markWaitingForRetry(message: "backward timeout close failed: \(String(describing: error))")
        }
        emit(.timeout(relayURL: relayURL, subscriptionID: subscriptionID, message: "backward idle timeout"))
        await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .timeout)
    }

    private func cancelBackwardTimeout(relayURL: String, subscriptionID: String) {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        backwardTimeoutTasks[key]?.cancel()
        backwardTimeoutTasks[key] = nil
    }

    private func cancelBackwardTimeouts(relayURL: String) {
        let prefix = relayURL + "\n"
        for key in backwardTimeoutTasks.keys where key.hasPrefix(prefix) {
            backwardTimeoutTasks[key]?.cancel()
            backwardTimeoutTasks[key] = nil
        }
    }

    private func backwardTimeoutKey(relayURL: String, subscriptionID: String) -> String {
        relayURL + "\n" + subscriptionID
    }

    private func registerBackwardSubscription(
        relayURL: String,
        packet: NostrREQPacket,
        logicalGroupIDs: [String],
        workTicket: NostrRelayWorkTicket
    ) -> BackwardSubscriptionRegistration {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: packet.subscriptionID)
        var replacedWorkTicket: NostrRelayWorkTicket?
        if let previousProgress = backwardProgressBySubscriptionKey[key] {
            replacedWorkTicket = previousProgress.workTicket
            releaseBackwardSubscriptionDemand(previousProgress)
            backwardSubscriptionKeysByGroupID[previousProgress.groupID]?.remove(key)
            if backwardSubscriptionKeysByGroupID[previousProgress.groupID]?.isEmpty == true {
                backwardSubscriptionKeysByGroupID[previousProgress.groupID] = nil
            }
        }
        nextBackwardProgressGeneration &+= 1
        let generation = nextBackwardProgressGeneration
        backwardProgressBySubscriptionKey[key] = BackwardSubscriptionProgress(
            groupID: packet.groupID,
            logicalGroupIDs: logicalGroupIDs,
            relayURL: relayURL,
            subscriptionID: packet.subscriptionID,
            generation: generation,
            workTicket: workTicket
        )
        acquireBackwardSubscriptionDemand(
            relayURL: relayURL,
            subscriptionID: packet.subscriptionID,
            generation: generation
        )
        backwardSubscriptionKeysByGroupID[packet.groupID, default: []].insert(key)
        return BackwardSubscriptionRegistration(
            generation: generation,
            replacedWorkTicket: replacedWorkTicket
        )
    }

    @discardableResult
    private func rollbackBackwardSubscription(
        relayURL: String,
        subscriptionID: String,
        generation: UInt64
    ) -> Bool {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        guard let progress = backwardProgressBySubscriptionKey[key],
              progress.generation == generation
        else { return false }
        releaseBackwardSubscriptionDemand(progress)
        backwardProgressBySubscriptionKey[key] = nil
        backwardSubscriptionKeysByGroupID[progress.groupID]?.remove(key)
        if backwardSubscriptionKeysByGroupID[progress.groupID]?.isEmpty == true {
            backwardSubscriptionKeysByGroupID[progress.groupID] = nil
        }
        return true
    }

    private func hasBackwardProgress(relayURL: String, subscriptionID: String) -> Bool {
        backwardProgressBySubscriptionKey[backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)] != nil
    }

    private func hasPendingBackwardProgress(relayURL: String, subscriptionID: String) -> Bool {
        guard let progress = backwardProgressBySubscriptionKey[
            backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        ] else { return false }
        return progress.terminal == nil
    }

    private func incrementBackwardEventCount(relayURL: String, subscriptionID: String) {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        backwardProgressBySubscriptionKey[key]?.eventCount += 1
    }

    private func completeBackwardSubscription(
        relayURL: String,
        subscriptionID: String,
        terminal: BackwardSubscriptionTerminal
    ) async {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        guard var progress = backwardProgressBySubscriptionKey[key],
              progress.terminal == nil
        else { return }
        progress.terminal = terminal
        backwardProgressBySubscriptionKey[key] = progress
        releaseBackwardSubscriptionDemand(progress)
        await workScheduler.release(progress.workTicket)

        await emitBackwardCompletionIfGroupFinished(groupID: progress.groupID)
        await releaseRelaySessionIfUnneeded(relayURL)
    }

    private func emitBackwardCompletionIfGroupFinished(groupID: String) async {
        guard let groupKeys = backwardSubscriptionKeysByGroupID[groupID],
              !groupKeys.isEmpty
        else { return }
        let groupProgress = groupKeys.compactMap { backwardProgressBySubscriptionKey[$0] }
        guard groupProgress.count == groupKeys.count,
              groupProgress.allSatisfy({ $0.terminal != nil })
        else { return }

        let logicalGroupIDs = groupProgress
            .flatMap(\.logicalGroupIDs)
            .dedupedPreservingOrder()
        let relayURLs = Array(Set(groupProgress.map(\.relayURL))).sorted()
        let subscriptionIDs = Array(Set(groupProgress.map(\.subscriptionID))).sorted()
        let eventCount = groupProgress.reduce(0) { $0 + $1.eventCount }
        let eoseCount = groupProgress.filter { $0.terminal == .eose }.count
        let closedCount = groupProgress.filter { $0.terminal == .closed }.count
        let timeoutCount = groupProgress.filter { $0.terminal == .timeout }.count

        for groupKey in groupKeys {
            backwardProgressBySubscriptionKey[groupKey] = nil
        }
        backwardSubscriptionKeysByGroupID[groupID] = nil
        for logicalGroupID in logicalGroupIDs {
            let completion = NostrBackwardREQCompletion(
                groupID: logicalGroupID,
                relayURLs: relayURLs,
                subscriptionIDs: subscriptionIDs,
                eventCount: eventCount,
                eoseCount: eoseCount,
                closedCount: closedCount,
                timeoutCount: timeoutCount
            )
            emit(.backwardCompleted(completion))
            if completion.groupID.hasPrefix("astrenza-heartbeat-") {
                await handleHeartbeatCompletion(completion)
            }
        }
    }

    private func handleHeartbeatCompletion(_ completion: NostrBackwardREQCompletion) async {
        for relayURL in completion.relayURLs {
            if completion.status == .completed {
                heartbeatMissCounts[relayURL] = 0
                continue
            }

            let missCount = (heartbeatMissCounts[relayURL] ?? 0) + 1
            heartbeatMissCounts[relayURL] = missCount
            guard missCount >= heartbeatPolicy.reconnectAfterMisses else { continue }
            heartbeatMissCounts[relayURL] = 0
            await reconnectAfterHeartbeatMiss(relayURL: relayURL, missCount: missCount, status: completion.status)
        }
    }

    private func reconnectAfterHeartbeatMiss(
        relayURL: String,
        missCount: Int,
        status: NostrBackwardREQCompletionStatus
    ) async {
        guard let session = sessions[relayURL] else { return }
        let state = await session.state()
        guard state != .suspended, state != .terminated else { return }

        await session.markWaitingForRetry(message: "heartbeat \(status.noticeDescription) \(missCount) time(s)")
        do {
            try await session.reconnectRestoringSubscriptions(
                replacingPackets: prepareForwardReconnectPackets(relayURL: relayURL)
            )
        } catch {
            await session.markWaitingForRetry(message: "heartbeat reconnect failed: \(String(describing: error))")
        }
    }

    private func completeBackwardProgress(
        relayURL: String,
        terminal: BackwardSubscriptionTerminal
    ) async {
        let prefix = relayURL + "\n"
        let keys = backwardProgressBySubscriptionKey.keys.filter { $0.hasPrefix(prefix) }
        for key in keys {
            guard let progress = backwardProgressBySubscriptionKey[key] else { continue }
            cancelBackwardTimeout(relayURL: progress.relayURL, subscriptionID: progress.subscriptionID)
            await completeBackwardSubscription(
                relayURL: progress.relayURL,
                subscriptionID: progress.subscriptionID,
                terminal: terminal
            )
        }
    }

    func retainBootstrapRelay(
        _ relayURL: String,
        scopeID: UUID
    ) async throws {
        guard let identity = NostrRelayURL(relayURL) else {
            throw NostrRelayClientError.invalidRelayURL(relayURL)
        }
        let didInsert = bootstrapRelayURLsByScopeID[scopeID, default: []]
            .insert(identity.rawValue)
            .inserted
        guard didInsert else { return }

        relayDemands.acquire(.bootstrap(scopeID), for: [identity])
        await prepareDemandRelaySessions([identity.rawValue])
    }

    func finishBootstrapScope(
        _ scopeID: UUID,
        retainUntilDefaultRelayHandoff: Bool
    ) async {
        guard bootstrapRelayURLsByScopeID[scopeID] != nil else { return }
        if retainUntilDefaultRelayHandoff {
            completedBootstrapScopeIDs.insert(scopeID)
            return
        }
        await releaseBootstrapScope(scopeID)
    }

    private func releaseCompletedBootstrapScopes() async {
        let scopeIDs = completedBootstrapScopeIDs
        for scopeID in scopeIDs {
            await releaseBootstrapScope(scopeID)
        }
    }

    private func releaseBootstrapScope(_ scopeID: UUID) async {
        completedBootstrapScopeIDs.remove(scopeID)
        let scopedRelayURLs = bootstrapRelayURLsByScopeID.removeValue(forKey: scopeID) ?? []
        let demand = NostrRelayDemand.bootstrap(scopeID)
        relayDemands.release(demand, from: relayIdentities(scopedRelayURLs))
        for relayURL in scopedRelayURLs {
            await releaseRelaySessionIfUnneeded(relayURL)
        }
    }

    private func prepareDemandRelaySessions(_ relayURLs: [String]) async {
        for relayURL in relayURLs where sessions[relayURL] == nil {
            scheduleRelayInformationFetch(relayURL: relayURL)
            let session = NostrRelaySession(
                relayURL: relayURL,
                transport: transportFactory(relayURL),
                eventValidator: eventValidator
            )
            await session.configureTraffic(accountID: trafficAccountID, policy: trafficPolicy)
            sessions[relayURL] = session
            await startPump(for: session, relayURL: relayURL)
        }
    }

    private func publish(
        event: NostrEvent,
        relayURL: String,
        timeoutNanoseconds: UInt64
    ) async -> NostrOutboxRelayPublishResult {
        guard let identity = NostrRelayURL(relayURL) else {
            return NostrOutboxRelayPublishResult(
                relayURL: relayURL,
                accepted: false,
                message: "invalid relay URL"
            )
        }

        let demand = NostrRelayDemand.publish(
            eventID: event.id,
            attemptID: UUID()
        )
        relayDemands.acquire(demand, for: [identity])
        await prepareDemandRelaySessions([relayURL])

        let result: NostrOutboxRelayPublishResult
        if let session = sessions[relayURL] {
            do {
                try await session.connect()
                if receiveLoopTasks[relayURL] == nil {
                    startReceiveLoop(for: session, relayURL: relayURL)
                }
                let acknowledgement = try await session.publish(
                    event,
                    timeoutNanoseconds: timeoutNanoseconds
                )
                result = NostrOutboxRelayPublishResult(
                    relayURL: relayURL,
                    accepted: acknowledgement.accepted,
                    message: acknowledgement.message
                )
            } catch {
                result = NostrOutboxRelayPublishResult(
                    relayURL: relayURL,
                    accepted: false,
                    message: NostrOutboxRelayPublishError.message(for: error)
                )
            }
        } else {
            result = NostrOutboxRelayPublishResult(
                relayURL: relayURL,
                accepted: false,
                message: "relay connection unavailable"
            )
        }

        await releaseRelayDemand(demand, from: [relayURL])
        return result
    }

    private func releaseRelayDemand(
        _ demand: NostrRelayDemand,
        from relayURLs: [String]
    ) async {
        for relayURL in relayURLs {
            guard let identity = NostrRelayURL(relayURL) else { continue }
            relayDemands.release(demand, from: [identity])
            await releaseRelaySessionIfUnneeded(relayURL)
        }
    }

    private func acquireBackwardSubscriptionDemand(
        relayURL: String,
        subscriptionID: String,
        generation: UInt64
    ) {
        guard let identity = NostrRelayURL(relayURL) else { return }
        relayDemands.acquire(
            .backwardSubscription(subscriptionID: subscriptionID, generation: generation),
            for: [identity]
        )
    }

    private func releaseBackwardSubscriptionDemand(_ progress: BackwardSubscriptionProgress) {
        guard let identity = NostrRelayURL(progress.relayURL) else { return }
        relayDemands.release(
            .backwardSubscription(
                subscriptionID: progress.subscriptionID,
                generation: progress.generation
            ),
            from: [identity]
        )
    }

    private func fetchMergeField(for request: NostrRelayRequest) -> NostrREQMergeField {
        request.filters.contains { $0["ids"] != nil } ? .ids : .authors
    }

    private func fetchWorkPriority(for request: NostrRelayRequest) -> NostrRelayWorkPriority {
        let purpose = request.subscriptionID.lowercased()
        if purpose.contains("older") || purpose.contains("gap") || purpose.contains("backfill") {
            return .backfill
        }
        if purpose.contains("profile") || purpose.contains("kind0") ||
            purpose.contains("nip65") || purpose.contains("kind3") ||
            purpose.contains("outbox") {
            return .visibleDependency
        }
        return .userInitiated
    }

    private func appendPendingFetchEvent(
        _ event: NostrEvent,
        relayURL: String,
        subscriptionID: String
    ) {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        pendingFetchesBySubscriptionKey[key]?.eventsByID[event.id] = event
    }

    private func finishPendingFetch(
        relayURL: String,
        subscriptionID: String
    ) {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        guard let pending = pendingFetchesBySubscriptionKey.removeValue(forKey: key) else { return }
        pending.continuation.yield(pending.eventsByID.values.sorted(by: Self.fetchEventOrder))
        pending.continuation.finish()
    }

    private func failPendingFetch(
        relayURL: String,
        subscriptionID: String,
        error: any Error
    ) {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        guard let pending = pendingFetchesBySubscriptionKey.removeValue(forKey: key) else { return }
        pending.continuation.finish(throwing: error)
    }

    private func failPendingFetches(
        relayURL: String,
        error: any Error
    ) async {
        let pending = pendingFetchesBySubscriptionKey.values.filter { $0.relayURL == relayURL }
        for fetch in pending {
            failPendingFetch(
                relayURL: fetch.relayURL,
                subscriptionID: fetch.subscriptionID,
                error: error
            )
            await abandonBackwardSubscription(
                relayURL: fetch.relayURL,
                subscriptionID: fetch.subscriptionID
            )
        }
    }

    private func finishAllPendingFetches(with error: any Error) {
        let pending = pendingFetchesBySubscriptionKey.values
        pendingFetchesBySubscriptionKey = [:]
        for fetch in pending {
            fetch.continuation.finish(throwing: error)
        }
    }

    private func cancelFetch(
        relayURL: String,
        subscriptionID: String,
        error: any Error
    ) async {
        failPendingFetch(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            error: error
        )
        await abandonBackwardSubscription(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )
    }

    private func abandonBackwardSubscription(
        relayURL: String,
        subscriptionID: String
    ) async {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)
        cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
        guard let progress = backwardProgressBySubscriptionKey.removeValue(forKey: key) else {
            return
        }

        releaseBackwardSubscriptionDemand(progress)
        backwardSubscriptionKeysByGroupID[progress.groupID]?.remove(key)
        if backwardSubscriptionKeysByGroupID[progress.groupID]?.isEmpty == true {
            backwardSubscriptionKeysByGroupID[progress.groupID] = nil
        }
        await workScheduler.release(progress.workTicket)
        try? await sessions[relayURL]?.close(subscriptionID: subscriptionID)
        await releaseRelaySessionIfUnneeded(relayURL)
    }

    private func relayFetchError(forClosedMessage message: String) -> NostrRelayClientError {
        let lowercaseMessage = message.lowercased()
        if lowercaseMessage.contains("auth-required") {
            return .authRequired(challenge: message)
        }
        if lowercaseMessage.contains("payment-required") {
            return .paymentRequired(message)
        }
        return .relayClosed(message)
    }

    private static func fetchEventOrder(_ lhs: NostrEvent, _ rhs: NostrEvent) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id < rhs.id
        }
        return lhs.createdAt > rhs.createdAt
    }

    private func installOrQueueForward(
        _ packet: NostrREQPacket,
        relayURL: String,
        session: NostrRelaySession,
        installationPacket: NostrREQPacket? = nil
    ) async throws {
        let key = forwardClosedRetryKey(
            relayURL: relayURL,
            subscriptionID: packet.subscriptionID
        )
        let ticket: NostrRelayWorkTicket
        if let existingTicket = forwardWorkTickets[key] {
            ticket = existingTicket
        } else {
            guard let identity = NostrRelayURL(relayURL) else {
                throw NostrRelayRuntimeError.connectionUnavailable(relayURL: relayURL)
            }
            ticket = await workScheduler.enqueue(
                relayURL: identity,
                subscriptionID: packet.subscriptionID,
                priority: .realtime
            )
            forwardWorkTickets[key] = ticket
        }

        if await workScheduler.isActive(ticket) {
            forwardActivationTasks.removeValue(forKey: key)?.cancel()
            try await session.install(installationPacket ?? packet)
            return
        }
        scheduleForwardActivation(
            ticket: ticket,
            desiredPacket: packet,
            installationPacket: installationPacket ?? packet,
            relayURL: relayURL,
            session: session
        )
    }

    private func scheduleForwardActivation(
        ticket: NostrRelayWorkTicket,
        desiredPacket: NostrREQPacket,
        installationPacket: NostrREQPacket,
        relayURL: String,
        session: NostrRelaySession
    ) {
        let key = forwardClosedRetryKey(
            relayURL: relayURL,
            subscriptionID: desiredPacket.subscriptionID
        )
        forwardActivationTasks[key]?.cancel()
        forwardActivationTasks[key] = Task {
            do {
                try await self.workScheduler.waitUntilActive(ticket)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.installActivatedForward(
                ticket: ticket,
                desiredPacket: desiredPacket,
                installationPacket: installationPacket,
                relayURL: relayURL,
                session: session
            )
        }
    }

    private func installActivatedForward(
        ticket: NostrRelayWorkTicket,
        desiredPacket: NostrREQPacket,
        installationPacket: NostrREQPacket,
        relayURL: String,
        session: NostrRelaySession
    ) async {
        let key = forwardClosedRetryKey(
            relayURL: relayURL,
            subscriptionID: desiredPacket.subscriptionID
        )
        forwardActivationTasks[key] = nil
        guard forwardWorkTickets[key] == ticket,
              activeForwardPackets[desiredPacket.subscriptionID] == desiredPacket,
              sessions[relayURL] === session
        else {
            await releaseForwardWorkTicket(
                relayURL: relayURL,
                subscriptionID: desiredPacket.subscriptionID
            )
            return
        }
        do {
            try await session.install(installationPacket)
            cancelForwardClosedRetry(
                relayURL: relayURL,
                subscriptionID: desiredPacket.subscriptionID,
                resetAttempts: false
            )
        } catch {
            await releaseForwardWorkTicket(
                relayURL: relayURL,
                subscriptionID: desiredPacket.subscriptionID
            )
            await session.markWaitingForRetry(
                message: "queued forward REQ failed: \(String(describing: error))"
            )
            if autoReceive {
                scheduleForwardRetryAfterClosed(
                    relayURL: relayURL,
                    subscriptionID: desiredPacket.subscriptionID
                )
            }
        }
    }

    private func releaseForwardWorkTicket(relayURL: String, subscriptionID: String) async {
        let key = forwardClosedRetryKey(
            relayURL: relayURL,
            subscriptionID: subscriptionID
        )
        forwardActivationTasks.removeValue(forKey: key)?.cancel()
        guard let ticket = forwardWorkTickets.removeValue(forKey: key) else { return }
        await workScheduler.release(ticket)
    }

    private func releaseForwardWorkTickets(relayURL: String) async {
        let prefix = relayURL + "\n"
        let subscriptionIDs = forwardWorkTickets
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value.subscriptionID)
        for subscriptionID in subscriptionIDs {
            await releaseForwardWorkTicket(
                relayURL: relayURL,
                subscriptionID: subscriptionID
            )
        }
    }

    private func releaseRelaySessionIfUnneeded(_ relayURL: String) async {
        guard let identity = NostrRelayURL(relayURL),
              !relayDemands.hasDemand(for: identity),
              let session = sessions.removeValue(forKey: relayURL)
        else { return }

        receiveLoopTasks.removeValue(forKey: relayURL)?.cancel()
        heartbeatLoopTasks.removeValue(forKey: relayURL)?.cancel()
        heartbeatMissCounts[relayURL] = nil
        forwardReconnectTracker.removeRelay(relayURL)
        cancelForwardClosedRetries(relayURL: relayURL)
        await releaseForwardWorkTickets(relayURL: relayURL)
        cancelBackwardTimeouts(relayURL: relayURL)
        let sessionPumpTask = sessionPumpTasks.removeValue(forKey: relayURL)
        await session.terminate()
        await sessionPumpTask?.value
    }

    private func scheduleRelayInformationFetch(relayURL: String) {
        guard let relayInformationFetcher,
              relayInformationTasks[relayURL] == nil
        else { return }
        relayInformationTasks[relayURL] = Task { [weak self] in
            let information = try? await relayInformationFetcher.information(for: relayURL)
            guard !Task.isCancelled else { return }
            await self?.finishRelayInformationFetch(
                relayURL: relayURL,
                information: information
            )
        }
    }

    private func finishRelayInformationFetch(
        relayURL: String,
        information: NostrRelayInformationDocument?
    ) async {
        relayInformationTasks[relayURL] = nil
        guard let information else { return }
        await applyRelayInformation(information, relayURL: relayURL)
    }

    private func backwardWorkPriority(for packet: NostrREQPacket) -> NostrRelayWorkPriority {
        let purpose = packet.groupID.lowercased()
        if purpose.contains("heartbeat") {
            return .maintenance
        }
        if purpose.contains("older") || purpose.contains("gap") || purpose.contains("backfill") {
            return .backfill
        }
        if purpose.contains("profile") || purpose.contains("kind0") || purpose.contains("source") {
            return .visibleDependency
        }
        return .userInitiated
    }

    private func prepareForwardReconnectPackets(
        relayURL: String
    ) -> [String: NostrREQPacket] {
        let packets = activeForwardPackets.values.filter { packet in
            packet.relayURLs.isEmpty ||
                canonicalRelayURLs(packet.relayURLs).contains(relayURL)
        }
        return prepareForwardReconnectPackets(
            relayURL: relayURL,
            packets: packets
        )
    }

    private func prepareForwardReconnectPackets(
        relayURL: String,
        packets: [NostrREQPacket]
    ) -> [String: NostrREQPacket] {
        forwardReconnectTracker.prepareReconnectPackets(
            relayURL: relayURL,
            packets: packets,
            overlapSeconds: reconnectOverlapSeconds
        )
    }

    private static func milliseconds(_ nanoseconds: UInt64) -> UInt64 {
        nanoseconds / 1_000_000
    }

    private func canonicalRelayURLs(for packet: NostrREQPacket) -> [String] {
        packet.relayURLs.isEmpty ? relayURLs : canonicalRelayURLs(packet.relayURLs)
    }

    private func forwardRelayURLs(for packet: NostrREQPacket) -> [String] {
        guard !packet.relayURLs.isEmpty else { return relayURLs }
        let scopedRelayURLs = Set(canonicalRelayURLs(packet.relayURLs))
        return relayURLs.filter(scopedRelayURLs.contains)
    }

    private func canonicalRelayURLs(_ relayURLs: [String]) -> [String] {
        NostrRelayURL.normalizedStrings(relayURLs)
    }

    private func relayIdentities<S: Sequence>(_ relayURLs: S) -> [NostrRelayURL]
    where S.Element == String {
        relayURLs.compactMap(NostrRelayURL.init)
    }
}

private extension Array where Element == String {
    func dedupedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private enum BackwardSubscriptionTerminal: Equatable {
    case eose
    case closed
    case timeout
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

private struct BackwardSubscriptionProgress: Equatable {
    let groupID: String
    let logicalGroupIDs: [String]
    let relayURL: String
    let subscriptionID: String
    let generation: UInt64
    let workTicket: NostrRelayWorkTicket
    var eventCount: Int = 0
    var terminal: BackwardSubscriptionTerminal?
}

private struct PendingRelayFetch {
    let relayURL: String
    let subscriptionID: String
    let continuation: AsyncThrowingStream<[NostrEvent], any Error>.Continuation
    var eventsByID: [String: NostrEvent] = [:]
}

private struct BackwardInstallTarget: Sendable {
    let relayURL: String
    let packet: NostrREQPacket
    let session: NostrRelaySession
    let generation: UInt64
    let workTicket: NostrRelayWorkTicket
}

private struct BackwardSubscriptionRegistration: Sendable {
    let generation: UInt64
    let replacedWorkTicket: NostrRelayWorkTicket?
}

private struct BackwardScheduledPacket: Sendable {
    let packet: NostrREQPacket
    let logicalGroupIDs: [String]
}
