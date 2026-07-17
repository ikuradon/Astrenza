import Foundation
import NostrCryptoAPI
import NostrCryptoSecp256k1
import NostrProtocol
import NostrStoreAPI

public enum NostrRelayRuntimePacket: Equatable, Sendable {
    case stateChanged(relayURL: String, state: NostrRelayConnectionState)
    case traffic(NostrRelayTrafficDelta)
    case requestStarted(NostrRelayRequestAttempt)
    case requestInstalled(requestID: String, relayURL: String, subscriptionID: String, installedAt: Int)
    case requestEnded(NostrRelayRequestAttemptEnd)
    case event(relayURL: String, subscriptionID: String, event: NostrEvent)
    case eose(relayURL: String, subscriptionID: String)
    case closed(relayURL: String, subscriptionID: String, message: String)
    case timeout(relayURL: String, subscriptionID: String, message: String)
    case backwardCompleted(NostrBackwardREQCompletion)
    case notice(relayURL: String, message: String)
    case auth(relayURL: String, challenge: String)
}

public protocol NostrRelayTransport: Sendable {
    func connect(relayURL: String) async throws -> any NostrRelayTransportConnection
}

public protocol NostrRelayTransportConnection: Sendable {
    func send(_ textFrame: String) async throws
    func receive() async throws -> String
    func close() async
}

public struct NostrRelayPublishAcknowledgement: Equatable, Sendable {
    public let accepted: Bool
    public let message: String

    public init(accepted: Bool, message: String) {
        self.accepted = accepted
        self.message = message
    }
}

public actor NostrRelaySession {
    public let relayURL: String

    private let transport: any NostrRelayTransport
    private let eventValidator: any NostrEventValidating
    private var connection: (any NostrRelayTransportConnection)?
    private var connectionGeneration: UInt64 = 0
    private var connectionAttemptID: UUID?
    private var connectionAttemptTask: Task<any NostrRelayTransportConnection, Error>?
    private var connectionState: NostrRelayConnectionState = .initialized
    private var activeSubscriptions: [String: SubscriptionRegistration] = [:]
    private var subscriptionGenerations: [String: UInt64] = [:]
    private var pendingPublishes: [UUID: PendingPublish] = [:]
    private var pendingPublishIDsByEventID: [String: [UUID]] = [:]
    private var continuations: [UUID: AsyncStream<NostrRelayRuntimePacket>.Continuation] = [:]
    private var trafficMeter: NostrRelayTrafficMeter?

    public init(
        relayURL: String,
        transport: any NostrRelayTransport,
        eventValidator: any NostrEventValidating = NostrEventValidator()
    ) {
        self.relayURL = relayURL
        self.transport = transport
        self.eventValidator = eventValidator
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

    public func state() -> NostrRelayConnectionState {
        connectionState
    }

    public func activeSubscriptionIDs() -> [String] {
        activeSubscriptions.keys.sorted()
    }

    public func configureTraffic(accountID: String?, policy: NostrSyncPolicy) {
        guard let accountID else {
            trafficMeter = nil
            return
        }
        trafficMeter = NostrRelayTrafficMeter(
            accountID: accountID,
            relayURL: relayURL,
            policy: policy
        )
    }

    public func connect() async throws {
        guard connectionState != .terminated else {
            throw NostrRelayRuntimeError.connectionUnavailable(relayURL: relayURL)
        }
        guard connection == nil else { return }
        do {
            _ = try await establishConnection(startingState: .connecting)
        } catch {
            if connection == nil {
                setState(.error)
            }
            throw error
        }
    }

    public func reconnectRestoringSubscriptions(
        replacingPackets: [String: NostrREQPacket] = [:]
    ) async throws {
        guard connectionState != .terminated else {
            throw NostrRelayRuntimeError.connectionUnavailable(relayURL: relayURL)
        }
        let previousConnection = connection
        connection = nil
        connectionGeneration &+= 1
        failAllPendingPublishes(
            with: NostrRelayRuntimeError.connectionUnavailable(relayURL: relayURL)
        )
        setState(.retrying)
        await previousConnection?.close()
        do {
            replaceActiveSubscriptionPackets(replacingPackets)
            let restoredConnection = try await establishConnection(startingState: nil)
            let restoredConnectionGeneration = connectionGeneration
            let registrations = Array(activeSubscriptions.values)
            for registration in registrations {
                let subscriptionID = registration.packet.subscriptionID
                guard activeSubscriptions[subscriptionID]?.generation == registration.generation else { continue }
                guard let attempt = beginRequestAttempt(
                    packet: registration.packet,
                    generation: registration.generation
                ) else { continue }
                do {
                    try await send(registration.packet.relayRequest.textFrame(), connection: restoredConnection)
                    guard connectionState != .terminated,
                          connectionGeneration == restoredConnectionGeneration,
                          activeSubscriptions[subscriptionID]?.generation == registration.generation
                    else { return }
                    emit(.requestInstalled(
                        requestID: attempt.requestID,
                        relayURL: relayURL,
                        subscriptionID: subscriptionID,
                        installedAt: Int(Date().timeIntervalSince1970)
                    ))
                } catch {
                    finishRequestAttempt(
                        requestID: attempt.requestID,
                        subscriptionID: subscriptionID,
                        reason: .installFailed,
                        message: String(describing: error)
                    )
                    guard connectionGeneration == restoredConnectionGeneration else { return }
                    connection = nil
                    connectionGeneration &+= 1
                    await restoredConnection.close()
                    throw error
                }
            }
        } catch {
            if connection == nil {
                setState(.waitingForRetry)
            }
            throw error
        }
    }

    public func install(_ packet: NostrREQPacket) async throws {
        let subscriptionID = packet.subscriptionID
        let previousRegistration = activeSubscriptions[subscriptionID]
        if let previousRequestID = previousRegistration?.requestID {
            finishRequestAttempt(
                requestID: previousRequestID,
                subscriptionID: subscriptionID,
                reason: .superseded
            )
        }
        let generation = nextSubscriptionGeneration(subscriptionID: subscriptionID)
        activeSubscriptions[subscriptionID] = SubscriptionRegistration(
            packet: packet,
            generation: generation,
            requestID: nil
        )

        if connection == nil {
            do {
                try await connect()
            } catch {
                rollbackInstallation(
                    subscriptionID: subscriptionID,
                    generation: generation,
                    previousRegistration: previousRegistration
                )
                throw error
            }
        }
        guard subscriptionGenerations[subscriptionID] == generation,
              activeSubscriptions[subscriptionID]?.generation == generation
        else { return }
        guard let connection else {
            rollbackInstallation(
                subscriptionID: subscriptionID,
                generation: generation,
                previousRegistration: previousRegistration
            )
            throw NostrRelayRuntimeError.connectionUnavailable(relayURL: relayURL)
        }
        let sendConnectionGeneration = connectionGeneration
        guard let attempt = beginRequestAttempt(packet: packet, generation: generation) else { return }

        do {
            try await send(packet.relayRequest.textFrame(), connection: connection)
            guard connectionState != .terminated,
                  connectionGeneration == sendConnectionGeneration,
                  subscriptionGenerations[subscriptionID] == generation,
                  activeSubscriptions[subscriptionID]?.generation == generation
            else { return }
            emit(.requestInstalled(
                requestID: attempt.requestID,
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                installedAt: Int(Date().timeIntervalSince1970)
            ))
        } catch {
            finishRequestAttempt(
                requestID: attempt.requestID,
                subscriptionID: subscriptionID,
                reason: .installFailed,
                message: String(describing: error)
            )
            guard connectionGeneration == sendConnectionGeneration else { return }
            rollbackInstallation(
                subscriptionID: subscriptionID,
                generation: generation,
                previousRegistration: previousRegistration
            )
            throw error
        }
    }

    public func publish(
        _ event: NostrEvent,
        timeoutNanoseconds: UInt64 = 7_000_000_000
    ) async throws -> NostrRelayPublishAcknowledgement {
        if connection == nil {
            try await connect()
        }
        guard let connection else {
            throw NostrRelayRuntimeError.connectionUnavailable(relayURL: relayURL)
        }

        let channel = AsyncThrowingStream<NostrRelayPublishAcknowledgement, Error>.makeStream()
        let attemptID = UUID()
        pendingPublishes[attemptID] = PendingPublish(
            eventID: event.id,
            continuation: channel.continuation
        )
        pendingPublishIDsByEventID[event.id, default: []].append(attemptID)
        do {
            try await send(Self.eventFrame(event), connection: connection)
        } catch {
            failPendingPublish(attemptID: attemptID, with: error)
            throw error
        }

        do {
            return try await Self.waitForPublishAcknowledgement(
                channel.stream,
                timeoutNanoseconds: timeoutNanoseconds
            )
        } catch {
            failPendingPublish(attemptID: attemptID, with: error)
            throw error
        }
    }

    public func close(
        subscriptionID: String,
        requestEndReason: NostrRelayRequestAttemptEndReason? = .cancelled
    ) async throws {
        let activeRequestID = activeSubscriptions[subscriptionID]?.requestID
        _ = nextSubscriptionGeneration(subscriptionID: subscriptionID)
        activeSubscriptions.removeValue(forKey: subscriptionID)
        if let activeRequestID, let requestEndReason {
            emitRequestAttemptEnd(
                requestID: activeRequestID,
                subscriptionID: subscriptionID,
                reason: requestEndReason
            )
        }
        guard let connection else {
            return
        }
        let sendConnectionGeneration = connectionGeneration
        do {
            try await send(Self.closeFrame(subscriptionID: subscriptionID), connection: connection)
        } catch {
            guard connectionGeneration == sendConnectionGeneration else { return }
            throw error
        }
    }

    public func receiveNext() async throws {
        try Task.checkCancellation()
        guard let connection else {
            throw NostrRelayRuntimeError.connectionUnavailable(relayURL: relayURL)
        }
        let raw = try await connection.receive()
        try Task.checkCancellation()
        recordReceived(raw)
        guard let message = NostrRelayMessage.parse(raw) else { return }

        switch message {
        case .event(let subscriptionID, let event):
            guard let packet = activeSubscriptions[subscriptionID]?.packet,
                  eventValidator.isValid(event),
                  NostrRelayFilterMatcher.matches(event: event, filters: packet.filters)
            else { return }
            emit(.event(relayURL: relayURL, subscriptionID: subscriptionID, event: event))
        case .eose(let subscriptionID):
            guard let registration = activeSubscriptions[subscriptionID] else { return }
            let packet = registration.packet
            emit(.eose(relayURL: relayURL, subscriptionID: subscriptionID))
            if packet.strategy == .backward {
                _ = nextSubscriptionGeneration(subscriptionID: subscriptionID)
                activeSubscriptions.removeValue(forKey: subscriptionID)
                try await send(Self.closeFrame(subscriptionID: subscriptionID), connection: connection)
            } else if activeSubscriptions[subscriptionID]?.generation == registration.generation {
                activeSubscriptions[subscriptionID]?.requestID = nil
            }
        case .ok(let eventID, let accepted, let message):
            resolvePendingPublish(
                eventID: eventID,
                acknowledgement: NostrRelayPublishAcknowledgement(
                    accepted: accepted,
                    message: message
                )
            )
        case .closed(let subscriptionID, let message):
            _ = nextSubscriptionGeneration(subscriptionID: subscriptionID)
            activeSubscriptions.removeValue(forKey: subscriptionID)
            emit(.closed(relayURL: relayURL, subscriptionID: subscriptionID, message: message))
            if message.lowercased().contains("auth-required") {
                emit(.auth(relayURL: relayURL, challenge: message))
            }
        case .notice(let message):
            emit(.notice(relayURL: relayURL, message: message))
        case .auth(let challenge):
            emit(.auth(relayURL: relayURL, challenge: challenge))
            failAllPendingPublishes(
                with: NostrOutboxRelayPublishError.authRequired(challenge)
            )
        }
    }

    public func markWaitingForRetry(message: String? = nil) {
        setState(.waitingForRetry)
        if let message {
            emit(.notice(relayURL: relayURL, message: message))
        }
    }

    public func markSuspended(message: String? = nil) {
        setState(.suspended)
        if let message {
            emit(.notice(relayURL: relayURL, message: message))
        }
    }

    public func terminate() async {
        connectionAttemptTask?.cancel()
        connectionAttemptTask = nil
        connectionAttemptID = nil
        for registration in activeSubscriptions.values {
            if let requestID = registration.requestID {
                emitRequestAttemptEnd(
                    requestID: requestID,
                    subscriptionID: registration.packet.subscriptionID,
                    reason: .cancelled
                )
            }
        }
        let connectionToClose = connection
        connection = nil
        connectionGeneration &+= 1
        failAllPendingPublishes(with: CancellationError())
        activeSubscriptions = [:]
        subscriptionGenerations = [:]
        setState(.terminated)
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations = [:]
        await connectionToClose?.close()
    }

    private func setState(_ state: NostrRelayConnectionState) {
        guard connectionState != .terminated || state == .terminated else { return }
        guard connectionState != state else { return }
        connectionState = state
        emit(.stateChanged(relayURL: relayURL, state: state))
    }

    private func emit(_ packet: NostrRelayRuntimePacket) {
        for continuation in continuations.values {
            continuation.yield(packet)
        }
    }

    private func removeContinuation(observerID: UUID) {
        continuations[observerID] = nil
    }

    private func establishConnection(
        startingState: NostrRelayConnectionState?
    ) async throws -> any NostrRelayTransportConnection {
        guard connectionState != .terminated else {
            throw NostrRelayRuntimeError.connectionUnavailable(relayURL: relayURL)
        }
        if let connection {
            return connection
        }

        let attemptID: UUID
        let attemptTask: Task<any NostrRelayTransportConnection, Error>
        if let existingAttemptID = connectionAttemptID,
           let existingAttemptTask = connectionAttemptTask {
            attemptID = existingAttemptID
            attemptTask = existingAttemptTask
        } else {
            let newAttemptID = UUID()
            let transport = transport
            let relayURL = relayURL
            let newAttemptTask = Task<any NostrRelayTransportConnection, Error> {
                try await transport.connect(relayURL: relayURL)
            }
            attemptID = newAttemptID
            attemptTask = newAttemptTask
            connectionAttemptID = newAttemptID
            connectionAttemptTask = newAttemptTask
            if let startingState {
                setState(startingState)
            }
        }

        do {
            let candidate = try await attemptTask.value
            if let connection {
                return connection
            }
            guard connectionAttemptID == attemptID else {
                await candidate.close()
                throw NostrRelayRuntimeError.connectionUnavailable(relayURL: relayURL)
            }
            connectionAttemptID = nil
            connectionAttemptTask = nil
            connection = candidate
            connectionGeneration &+= 1
            setState(.connected)
            return candidate
        } catch {
            if connectionAttemptID == attemptID {
                connectionAttemptID = nil
                connectionAttemptTask = nil
            }
            throw error
        }
    }

    private func nextSubscriptionGeneration(subscriptionID: String) -> UInt64 {
        let generation = (subscriptionGenerations[subscriptionID] ?? 0) &+ 1
        subscriptionGenerations[subscriptionID] = generation
        return generation
    }

    private func replaceActiveSubscriptionPackets(
        _ packets: [String: NostrREQPacket]
    ) {
        for (subscriptionID, packet) in packets
        where packet.subscriptionID == subscriptionID &&
            activeSubscriptions[subscriptionID] != nil {
            activeSubscriptions[subscriptionID]?.packet = packet
        }
    }

    private func rollbackInstallation(
        subscriptionID: String,
        generation: UInt64,
        previousRegistration: SubscriptionRegistration?
    ) {
        guard subscriptionGenerations[subscriptionID] == generation else { return }
        if let previousRegistration {
            let rollbackGeneration = nextSubscriptionGeneration(subscriptionID: subscriptionID)
            activeSubscriptions[subscriptionID] = SubscriptionRegistration(
                packet: previousRegistration.packet,
                generation: rollbackGeneration,
                requestID: nil
            )
        } else {
            _ = nextSubscriptionGeneration(subscriptionID: subscriptionID)
            activeSubscriptions.removeValue(forKey: subscriptionID)
        }
    }

    private func send(_ textFrame: String) async throws {
        guard let connection else { return }
        try await send(textFrame, connection: connection)
    }

    private func send(_ textFrame: String, connection: any NostrRelayTransportConnection) async throws {
        try await connection.send(textFrame)
        recordSent(textFrame)
    }

    private func resolvePendingPublish(
        eventID: String,
        acknowledgement: NostrRelayPublishAcknowledgement
    ) {
        guard let attemptID = pendingPublishIDsByEventID[eventID]?.first,
              let pending = removePendingPublish(attemptID: attemptID)
        else { return }
        pending.continuation.yield(acknowledgement)
        pending.continuation.finish()
    }

    private func failPendingPublish(attemptID: UUID, with error: any Error) {
        guard let pending = removePendingPublish(attemptID: attemptID) else { return }
        pending.continuation.finish(throwing: error)
    }

    private func failAllPendingPublishes(with error: any Error) {
        let pending = Array(pendingPublishes.values)
        pendingPublishes.removeAll(keepingCapacity: false)
        pendingPublishIDsByEventID.removeAll(keepingCapacity: false)
        for publish in pending {
            publish.continuation.finish(throwing: error)
        }
    }

    private func removePendingPublish(attemptID: UUID) -> PendingPublish? {
        guard let pending = pendingPublishes.removeValue(forKey: attemptID) else { return nil }
        pendingPublishIDsByEventID[pending.eventID]?.removeAll { $0 == attemptID }
        if pendingPublishIDsByEventID[pending.eventID]?.isEmpty == true {
            pendingPublishIDsByEventID[pending.eventID] = nil
        }
        return pending
    }

    private static func waitForPublishAcknowledgement(
        _ stream: AsyncThrowingStream<NostrRelayPublishAcknowledgement, Error>,
        timeoutNanoseconds: UInt64
    ) async throws -> NostrRelayPublishAcknowledgement {
        try await withThrowingTaskGroup(of: NostrRelayPublishAcknowledgement.self) { group in
            group.addTask {
                for try await acknowledgement in stream {
                    return acknowledgement
                }
                throw CancellationError()
            }
            group.addTask {
                if timeoutNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                }
                throw NostrOutboxRelayPublishError.timedOut
            }

            defer { group.cancelAll() }
            guard let acknowledgement = try await group.next() else {
                throw NostrOutboxRelayPublishError.timedOut
            }
            return acknowledgement
        }
    }

    private static func eventFrame(_ event: NostrEvent) throws -> String {
        let eventData = try JSONEncoder().encode(event)
        let eventObject = try JSONSerialization.jsonObject(with: eventData)
        let frame: [Any] = ["EVENT", eventObject]
        guard JSONSerialization.isValidJSONObject(frame) else {
            throw NostrOutboxRelayPublishError.invalidEventFrame
        }
        let data = try JSONSerialization.data(
            withJSONObject: frame,
            options: [.sortedKeys]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw NostrOutboxRelayPublishError.invalidEventFrame
        }
        return text
    }

    private func recordReceived(_ textFrame: String) {
        trafficMeter?.recordReceived(textFrame)
        flushTraffic()
    }

    private func recordSent(_ textFrame: String) {
        trafficMeter?.recordSent(textFrame)
        flushTraffic()
    }

    private func flushTraffic() {
        let occurredAt = Int(Date().timeIntervalSince1970)
        for delta in trafficMeter?.flush(occurredAt: occurredAt) ?? [] {
            emit(.traffic(delta))
        }
    }

    private func beginRequestAttempt(
        packet: NostrREQPacket,
        generation: UInt64
    ) -> NostrRelayRequestAttempt? {
        let subscriptionID = packet.subscriptionID
        guard activeSubscriptions[subscriptionID]?.generation == generation else { return nil }
        if let previousRequestID = activeSubscriptions[subscriptionID]?.requestID {
            emitRequestAttemptEnd(
                requestID: previousRequestID,
                subscriptionID: subscriptionID,
                reason: .superseded
            )
        }
        let attempt = NostrRelayRequestAttempt(
            requestID: UUID().uuidString,
            relayURL: relayURL,
            packet: packet,
            startedAt: Int(Date().timeIntervalSince1970)
        )
        activeSubscriptions[subscriptionID]?.requestID = attempt.requestID
        emit(.requestStarted(attempt))
        return attempt
    }

    private func finishRequestAttempt(
        requestID: String,
        subscriptionID: String,
        reason: NostrRelayRequestAttemptEndReason,
        message: String? = nil
    ) {
        if activeSubscriptions[subscriptionID]?.requestID == requestID {
            activeSubscriptions[subscriptionID]?.requestID = nil
        }
        emitRequestAttemptEnd(
            requestID: requestID,
            subscriptionID: subscriptionID,
            reason: reason,
            message: message
        )
    }

    private func emitRequestAttemptEnd(
        requestID: String,
        subscriptionID: String,
        reason: NostrRelayRequestAttemptEndReason,
        message: String? = nil
    ) {
        emit(.requestEnded(NostrRelayRequestAttemptEnd(
            requestID: requestID,
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            reason: reason,
            message: message,
            endedAt: Int(Date().timeIntervalSince1970)
        )))
    }

    private static func closeFrame(subscriptionID: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["CLOSE", subscriptionID], options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? #"["CLOSE",""]"#
    }
}

private struct SubscriptionRegistration: Sendable {
    var packet: NostrREQPacket
    let generation: UInt64
    var requestID: String?
}

private struct PendingPublish: Sendable {
    let eventID: String
    let continuation: AsyncThrowingStream<
        NostrRelayPublishAcknowledgement,
        Error
    >.Continuation
}
