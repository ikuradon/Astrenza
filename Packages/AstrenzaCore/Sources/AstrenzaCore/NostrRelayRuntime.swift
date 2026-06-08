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
    private var backwardTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var backwardProgressBySubscriptionKey: [String: BackwardSubscriptionProgress] = [:]
    private var backwardSubscriptionKeysByGroupID: [String: Set<String>] = [:]
    private var trafficAccountID: String?
    private var trafficPolicy = NostrSyncPolicy.default()
    private var continuation: AsyncStream<NostrRelayRuntimePacket>.Continuation?

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
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    public func defaultRelayURLs() -> [String] {
        relayURLs
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
        let removedRelays = Set(relayURLs).subtracting(normalizedRelays)
        let addedRelays = normalizedRelays.filter { sessions[$0] == nil }

        for relayURL in removedRelays {
            sessionPumpTasks[relayURL]?.cancel()
            sessionPumpTasks[relayURL] = nil
            receiveLoopTasks[relayURL]?.cancel()
            receiveLoopTasks[relayURL] = nil
            heartbeatLoopTasks[relayURL]?.cancel()
            heartbeatLoopTasks[relayURL] = nil
            heartbeatMissCounts[relayURL] = nil
            cancelBackwardTimeouts(relayURL: relayURL)
            cancelBackwardProgress(relayURL: relayURL)
            if let session = sessions.removeValue(forKey: relayURL) {
                await session.terminate()
            }
        }

        relayURLs = normalizedRelays

        for relayURL in addedRelays {
            let session = NostrRelaySession(
                relayURL: relayURL,
                transport: transportFactory(relayURL),
                eventValidator: eventValidator
            )
            await session.configureTraffic(accountID: trafficAccountID, policy: trafficPolicy)
            sessions[relayURL] = session
            await startPump(for: session, relayURL: relayURL)
            try await session.connect()
            if autoReceive {
                startReceiveLoop(for: session, relayURL: relayURL)
                startHeartbeatLoop(for: session, relayURL: relayURL)
            }
            for packet in activeForwardPackets.values {
                try await session.install(packet)
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
                guard let session = sessions[relayURL] else { continue }
                try? await session.close(subscriptionID: packet.subscriptionID)
            }
        }

        for packet in installPackets {
            let targetRelays = packet.relayURLs.isEmpty ? relayURLs : relayURLs.filter { packet.relayURLs.contains($0) }
            for relayURL in targetRelays {
                guard let session = sessions[relayURL] else { continue }
                try await session.install(packet)
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
        let installPackets = NostrREQScheduler.batch(backwardPackets, mergeField: mergeField)
            .flatMap { NostrREQScheduler.chunk($0, mergeField: mergeField, policy: chunkPolicy) }

        for packet in installPackets {
            let targetRelays = packet.relayURLs.isEmpty ? relayURLs : relayURLs.filter { packet.relayURLs.contains($0) }
            for relayURL in targetRelays {
                guard let session = sessions[relayURL] else { continue }
                try await session.install(packet)
                registerBackwardSubscription(relayURL: relayURL, packet: packet)
                scheduleBackwardIdleTimeout(relayURL: relayURL, subscriptionID: packet.subscriptionID)
            }
        }
    }

    public func sendHeartbeat(relayURL: String) async throws {
        let packet = NostrBackwardREQBuilder.heartbeat(relayURLs: [relayURL])
        try await installBackward([packet], mergeField: .ids)
    }

    public func receiveNext(relayURL: String) async throws {
        try await sessions[relayURL]?.receiveNext()
    }

    public func terminate() async {
        for task in sessionPumpTasks.values {
            task.cancel()
        }
        for task in receiveLoopTasks.values {
            task.cancel()
        }
        for task in heartbeatLoopTasks.values {
            task.cancel()
        }
        for task in backwardTimeoutTasks.values {
            task.cancel()
        }
        sessionPumpTasks = [:]
        receiveLoopTasks = [:]
        heartbeatLoopTasks = [:]
        heartbeatMissCounts = [:]
        backwardTimeoutTasks = [:]
        backwardProgressBySubscriptionKey = [:]
        backwardSubscriptionKeysByGroupID = [:]
        for session in sessions.values {
            await session.terminate()
        }
        sessions = [:]
        relayURLs = []
        activeForwardPackets = [:]
        continuation?.finish()
        continuation = nil
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
            if hasBackwardProgress(relayURL: relayURL, subscriptionID: subscriptionID) {
                incrementBackwardEventCount(relayURL: relayURL, subscriptionID: subscriptionID)
                scheduleBackwardIdleTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            }
        case .eose(let relayURL, let subscriptionID):
            cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .eose)
        case .closed(let relayURL, let subscriptionID, _):
            cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .closed)
        case .timeout(let relayURL, let subscriptionID, _):
            cancelBackwardTimeout(relayURL: relayURL, subscriptionID: subscriptionID)
            await completeBackwardSubscription(relayURL: relayURL, subscriptionID: subscriptionID, terminal: .timeout)
        case .stateChanged, .traffic, .notice, .auth, .backwardCompleted:
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
                    try await session.receiveNext()
                    retryAttempt = 0
                } catch {
                    await session.markWaitingForRetry(message: String(describing: error))
                    retryAttempt += 1
                    if retryAttempt > retryPolicy.maxAttempts {
                        await session.markSuspended(message: "retry attempts exhausted")
                        try? await Task.sleep(nanoseconds: retryPolicy.recoveryDelayNanoseconds(forAttempt: retryAttempt))
                        guard !Task.isCancelled else { break }
                        retryAttempt = 0
                    }

                    let delay = retryPolicy.delayNanoseconds(forAttempt: retryAttempt)
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }

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
        continuation?.yield(packet)
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
            try await sessions[relayURL]?.close(subscriptionID: subscriptionID)
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

    private func registerBackwardSubscription(relayURL: String, packet: NostrREQPacket) {
        let key = backwardTimeoutKey(relayURL: relayURL, subscriptionID: packet.subscriptionID)
        backwardProgressBySubscriptionKey[key] = BackwardSubscriptionProgress(
            groupID: packet.groupID,
            relayURL: relayURL,
            subscriptionID: packet.subscriptionID
        )
        backwardSubscriptionKeysByGroupID[packet.groupID, default: []].insert(key)
    }

    private func hasBackwardProgress(relayURL: String, subscriptionID: String) -> Bool {
        backwardProgressBySubscriptionKey[backwardTimeoutKey(relayURL: relayURL, subscriptionID: subscriptionID)] != nil
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

        guard let groupKeys = backwardSubscriptionKeysByGroupID[progress.groupID] else { return }
        let groupProgress = groupKeys.compactMap { backwardProgressBySubscriptionKey[$0] }
        guard groupProgress.count == groupKeys.count,
              groupProgress.allSatisfy({ $0.terminal != nil })
        else { return }

        let completion = NostrBackwardREQCompletion(
            groupID: progress.groupID,
            relayURLs: Array(Set(groupProgress.map(\.relayURL))).sorted(),
            subscriptionIDs: Array(Set(groupProgress.map(\.subscriptionID))).sorted(),
            eventCount: groupProgress.reduce(0) { $0 + $1.eventCount },
            eoseCount: groupProgress.filter { $0.terminal == .eose }.count,
            closedCount: groupProgress.filter { $0.terminal == .closed }.count,
            timeoutCount: groupProgress.filter { $0.terminal == .timeout }.count
        )

        for groupKey in groupKeys {
            backwardProgressBySubscriptionKey[groupKey] = nil
        }
        backwardSubscriptionKeysByGroupID[progress.groupID] = nil
        emit(.backwardCompleted(completion))
        if completion.groupID.hasPrefix("astrenza-heartbeat-") {
            await handleHeartbeatCompletion(completion)
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

    private func cancelBackwardProgress(relayURL: String) {
        let prefix = relayURL + "\n"
        let keys = backwardProgressBySubscriptionKey.keys.filter { $0.hasPrefix(prefix) }
        for key in keys {
            guard let progress = backwardProgressBySubscriptionKey.removeValue(forKey: key) else { continue }
            backwardSubscriptionKeysByGroupID[progress.groupID]?.remove(key)
            if backwardSubscriptionKeysByGroupID[progress.groupID]?.isEmpty == true {
                backwardSubscriptionKeysByGroupID[progress.groupID] = nil
            }
        }
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
    let relayURL: String
    let subscriptionID: String
    var eventCount: Int = 0
    var terminal: BackwardSubscriptionTerminal?
}
