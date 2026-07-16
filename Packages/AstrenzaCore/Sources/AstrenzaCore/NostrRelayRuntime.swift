import Foundation

public actor NostrRelayRuntime {
    public typealias TransportFactory = @Sendable (String) -> any NostrRelayTransport

    private let transportFactory: TransportFactory
    private let eventValidator: NostrEventValidator
    private let autoReceive: Bool
    private let retryPolicy: NostrRelayRuntimeRetryPolicy
    private let heartbeatPolicy: NostrRelayRuntimeHeartbeatPolicy
    private let backwardPolicy: NostrRelayRuntimeBackwardPolicy
    private var sessions: [String: NostrRelaySession] = [:]
    private var relayURLs: [String] = []
    private var activeForwardPackets: [String: NostrREQPacket] = [:]
    private var sessionPumpTasks: [String: Task<Void, Never>] = [:]
    private var receiveLoopTasks: [String: Task<Void, Never>] = [:]
    private var heartbeatLoopTasks: [String: Task<Void, Never>] = [:]
    private var heartbeatMissCounts: [String: Int] = [:]
    private var forwardClosedRetryTasks: [String: Task<Void, Never>] = [:]
    private var backwardTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var backwardProgressBySubscriptionKey: [String: BackwardSubscriptionProgress] = [:]
    private var backwardSubscriptionKeysByGroupID: [String: Set<String>] = [:]
    private var temporaryRelayLeaseCounts: [String: Int] = [:]
    private var nextBackwardProgressGeneration: UInt64 = 0
    private var trafficAccountID: String?
    private var trafficPolicy = NostrSyncPolicy.default()
    private var continuations: [UUID: AsyncStream<NostrRelayRuntimePacket>.Continuation] = [:]

    public init(
        transportFactory: @escaping TransportFactory,
        eventValidator: NostrEventValidator = NostrEventValidator(),
        autoReceive: Bool = true,
        retryPolicy: NostrRelayRuntimeRetryPolicy = NostrRelayRuntimeRetryPolicy(),
        heartbeatPolicy: NostrRelayRuntimeHeartbeatPolicy = NostrRelayRuntimeHeartbeatPolicy(),
        backwardPolicy: NostrRelayRuntimeBackwardPolicy = NostrRelayRuntimeBackwardPolicy()
    ) {
        self.transportFactory = transportFactory
        self.eventValidator = eventValidator
        self.autoReceive = autoReceive
        self.retryPolicy = retryPolicy
        self.heartbeatPolicy = heartbeatPolicy
        self.backwardPolicy = backwardPolicy
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
        let defaultRelays = Set(relayURLs)
        return sessions.keys.filter { !defaultRelays.contains($0) }.sorted()
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

    public func setTrafficContext(accountID: String?, policy: NostrSyncPolicy) async {
        trafficAccountID = accountID
        trafficPolicy = policy
        for session in sessions.values {
            await session.configureTraffic(accountID: accountID, policy: policy)
        }
    }

    public func setDefaultRelays(_ newRelayURLs: [String]) async throws {
        let normalizedRelays = newRelayURLs.dedupedPreservingOrder()
        let previousRelayURLs = Set(relayURLs)
        let removedRelays = Set(relayURLs).subtracting(normalizedRelays)
        let addedRelays = normalizedRelays.filter { !previousRelayURLs.contains($0) }

        for relayURL in removedRelays {
            let sessionPumpTask = sessionPumpTasks[relayURL]
            receiveLoopTasks[relayURL]?.cancel()
            receiveLoopTasks[relayURL] = nil
            heartbeatLoopTasks[relayURL]?.cancel()
            heartbeatLoopTasks[relayURL] = nil
            heartbeatMissCounts[relayURL] = nil
            cancelForwardClosedRetries(relayURL: relayURL)
            cancelBackwardTimeouts(relayURL: relayURL)
            await completeBackwardProgress(relayURL: relayURL, terminal: .closed)
            if let session = sessions.removeValue(forKey: relayURL) {
                await session.terminate()
                await sessionPumpTask?.value
            } else {
                sessionPumpTask?.cancel()
            }
            sessionPumpTasks[relayURL] = nil
        }

        relayURLs = normalizedRelays

        for relayURL in addedRelays {
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
            where packet.relayURLs.isEmpty || packet.relayURLs.contains(relayURL) {
                do {
                    try await session.install(packet)
                } catch {
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
        let installSubscriptionIDs = Set(installPackets.map(\.subscriptionID))
        activeForwardPackets = activeForwardPackets.filter { !shouldReplace($0.value) }
        for packet in installPackets {
            activeForwardPackets[packet.subscriptionID] = packet
        }

        for packet in previousPackets where !installSubscriptionIDs.contains(packet.subscriptionID) {
            let targetRelays = packet.relayURLs.isEmpty ? relayURLs : relayURLs.filter { packet.relayURLs.contains($0) }
            for relayURL in targetRelays {
                cancelForwardClosedRetry(relayURL: relayURL, subscriptionID: packet.subscriptionID)
                guard let session = sessions[relayURL] else { continue }
                try? await session.close(subscriptionID: packet.subscriptionID)
            }
        }

        for packet in installPackets {
            let targetRelays = packet.relayURLs.isEmpty ? relayURLs : relayURLs.filter { packet.relayURLs.contains($0) }
            for relayURL in targetRelays {
                guard let session = sessions[relayURL] else { continue }
                do {
                    try await session.install(packet)
                    cancelForwardClosedRetry(relayURL: relayURL, subscriptionID: packet.subscriptionID)
                } catch {
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
        chunkPolicy: NostrREQChunkPolicy = NostrREQChunkPolicy()
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
        let temporaryRelayURLs = scheduledPackets
            .flatMap(\.packet.relayURLs)
            .dedupedPreservingOrder()
            .filter { !relayURLs.contains($0) }
        retainTemporaryRelayLeases(temporaryRelayURLs)

        do {
            await prepareTemporaryRelaySessions(temporaryRelayURLs)
            try await installScheduledBackward(scheduledPackets)
        } catch {
            await releaseTemporaryRelayLeases(temporaryRelayURLs)
            throw error
        }
        await releaseTemporaryRelayLeases(temporaryRelayURLs)
    }

    private func installScheduledBackward(
        _ scheduledPackets: [BackwardScheduledPacket]
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
                guard let session = sessions[relayURL] else { continue }
                let generation = registerBackwardSubscription(
                    relayURL: relayURL,
                    packet: packet,
                    logicalGroupIDs: scheduledPacket.logicalGroupIDs
                )
                installTargets.append(BackwardInstallTarget(
                    relayURL: relayURL,
                    packet: packet,
                    session: session,
                    generation: generation
                ))
            }
        }

        var successfullyInstalledTargets: [BackwardInstallTarget] = []
        var firstInstallError: (any Error)?
        for target in installTargets {
            do {
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
                _ = rollbackBackwardSubscription(
                    relayURL: target.relayURL,
                    subscriptionID: target.packet.subscriptionID,
                    generation: target.generation
                )
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
        let candidates = packet.relayURLs.isEmpty
            ? relayURLs
            : packet.relayURLs.dedupedPreservingOrder()
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
        for task in backwardTimeoutTasks.values {
            task.cancel()
        }
        sessionPumpTasks = [:]
        receiveLoopTasks = [:]
        heartbeatLoopTasks = [:]
        heartbeatMissCounts = [:]
        forwardClosedRetryTasks = [:]
        backwardTimeoutTasks = [:]
        backwardProgressBySubscriptionKey = [:]
        backwardSubscriptionKeysByGroupID = [:]
        temporaryRelayLeaseCounts = [:]
        sessions = [:]
        relayURLs = []
        activeForwardPackets = [:]
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations = [:]
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
        case .event(let relayURL, let subscriptionID, _):
            if hasPendingBackwardProgress(relayURL: relayURL, subscriptionID: subscriptionID) {
                incrementBackwardEventCount(relayURL: relayURL, subscriptionID: subscriptionID)
                scheduleBackwardIdleTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            }
        case .eose(let relayURL, let subscriptionID):
            cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .eose)
        case .closed(let relayURL, let subscriptionID, let message):
            let wasBackwardSubscription = hasBackwardProgress(relayURL: relayURL, subscriptionID: subscriptionID)
            cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .closed)
            if !wasBackwardSubscription,
               NostrRelayClosedDisposition(message: message) == .retryAfterDelay {
                scheduleForwardRetryAfterClosed(relayURL: relayURL, subscriptionID: subscriptionID)
            }
        case .timeout(let relayURL, let subscriptionID, _):
            cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .timeout)
        case .stateChanged, .traffic, .requestStarted, .requestInstalled, .requestEnded,
             .notice, .auth, .backwardCompleted:
            break
        }

        emit(packet)
    }

    private func startReceiveLoop(for session: NostrRelaySession, relayURL: String) {
        receiveLoopTasks[relayURL]?.cancel()
        let retryPolicy = retryPolicy
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
                    await session.markWaitingForRetry(message: String(describing: error))
                    retryAttempt += 1
                    if retryAttempt > retryPolicy.maxAttempts {
                        await session.markSuspended(message: "retry attempts exhausted")
                        do {
                            try await Task.sleep(nanoseconds: retryPolicy.recoveryDelayNanoseconds(forAttempt: retryAttempt))
                        } catch {
                            break
                        }
                        retryAttempt = 0
                    }

                    let delay = retryPolicy.delayNanoseconds(forAttempt: retryAttempt)
                    if delay > 0 {
                        do {
                            try await Task.sleep(nanoseconds: delay)
                        } catch {
                            break
                        }
                    }
                    guard !Task.isCancelled else { break }

                    do {
                        try await session.reconnectRestoringSubscriptions()
                    } catch {
                        await session.markWaitingForRetry(message: String(describing: error))
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
        let delay = max(retryPolicy.delayNanoseconds(forAttempt: 1), 10_000_000)
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
              packet.relayURLs.isEmpty || packet.relayURLs.contains(relayURL),
              let session = sessions[relayURL]
        else { return }
        do {
            try await session.install(packet)
        } catch {
            await session.markWaitingForRetry(message: "forward REQ retry failed: \(String(describing: error))")
            scheduleForwardRetryAfterClosed(relayURL: relayURL, subscriptionID: subscriptionID)
        }
    }

    private func cancelForwardClosedRetry(relayURL: String, subscriptionID: String) {
        let key = forwardClosedRetryKey(relayURL: relayURL, subscriptionID: subscriptionID)
        forwardClosedRetryTasks[key]?.cancel()
        forwardClosedRetryTasks[key] = nil
    }

    private func cancelForwardClosedRetries(relayURL: String) {
        let prefix = relayURL + "\n"
        for key in forwardClosedRetryTasks.keys where key.hasPrefix(prefix) {
            forwardClosedRetryTasks[key]?.cancel()
            forwardClosedRetryTasks[key] = nil
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
        logicalGroupIDs: [String]
    ) -> UInt64 {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: packet.subscriptionID)
        if let previousProgress = backwardProgressBySubscriptionKey[key] {
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
            generation: generation
        )
        backwardSubscriptionKeysByGroupID[packet.groupID, default: []].insert(key)
        return generation
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

        await emitBackwardCompletionIfGroupFinished(groupID: progress.groupID)
        await releaseTemporaryRelaySessionIfUnused(relayURL)
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
            try await session.reconnectRestoringSubscriptions()
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

    private func retainTemporaryRelayLeases(_ relayURLs: [String]) {
        for relayURL in relayURLs {
            temporaryRelayLeaseCounts[relayURL, default: 0] += 1
        }
    }

    private func releaseTemporaryRelayLeases(_ relayURLs: [String]) async {
        for relayURL in relayURLs {
            let remainingCount = max(0, temporaryRelayLeaseCounts[relayURL, default: 0] - 1)
            temporaryRelayLeaseCounts[relayURL] = remainingCount == 0 ? nil : remainingCount
            await releaseTemporaryRelaySessionIfUnused(relayURL)
        }
    }

    private func prepareTemporaryRelaySessions(_ relayURLs: [String]) async {
        for relayURL in relayURLs where sessions[relayURL] == nil {
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

    private func releaseTemporaryRelaySessionIfUnused(_ relayURL: String) async {
        guard !relayURLs.contains(relayURL),
              temporaryRelayLeaseCounts[relayURL] == nil,
              !backwardProgressBySubscriptionKey.values.contains(where: {
                  $0.relayURL == relayURL && $0.terminal == nil
              }),
              let session = sessions.removeValue(forKey: relayURL)
        else { return }

        receiveLoopTasks.removeValue(forKey: relayURL)?.cancel()
        heartbeatLoopTasks.removeValue(forKey: relayURL)?.cancel()
        heartbeatMissCounts[relayURL] = nil
        cancelForwardClosedRetries(relayURL: relayURL)
        cancelBackwardTimeouts(relayURL: relayURL)
        sessionPumpTasks[relayURL] = nil
        await session.terminate()
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
    var eventCount: Int = 0
    var terminal: BackwardSubscriptionTerminal?
}

private struct BackwardInstallTarget: Sendable {
    let relayURL: String
    let packet: NostrREQPacket
    let session: NostrRelaySession
    let generation: UInt64
}

private struct BackwardScheduledPacket: Sendable {
    let packet: NostrREQPacket
    let logicalGroupIDs: [String]
}
