import Foundation

public enum NostrRelayRuntimePacket: Equatable, Sendable {
    case stateChanged(relayURL: String, state: NostrRelayConnectionState)
    case traffic(NostrRelayTrafficDelta)
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

public actor NostrRelaySession {
    public let relayURL: String

    private let transport: any NostrRelayTransport
    private let eventValidator: NostrEventValidator
    private var connection: (any NostrRelayTransportConnection)?
    private var connectionState: NostrRelayConnectionState = .initialized
    private var activeSubscriptions: [String: NostrREQPacket] = [:]
    private var continuation: AsyncStream<NostrRelayRuntimePacket>.Continuation?
    private var trafficMeter: NostrRelayTrafficMeter?

    public init(
        relayURL: String,
        transport: any NostrRelayTransport,
        eventValidator: NostrEventValidator = NostrEventValidator()
    ) {
        self.relayURL = relayURL
        self.transport = transport
        self.eventValidator = eventValidator
    }

    public func events() -> AsyncStream<NostrRelayRuntimePacket> {
        AsyncStream { continuation in
            self.continuation = continuation
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
        guard connection == nil else { return }
        setState(.connecting)
        do {
            connection = try await transport.connect(relayURL: relayURL)
            setState(.connected)
        } catch {
            setState(.error)
            throw error
        }
    }

    public func reconnectRestoringSubscriptions() async throws {
        let packets = Array(activeSubscriptions.values)
        await connection?.close()
        connection = nil
        setState(.retrying)
        do {
            connection = try await transport.connect(relayURL: relayURL)
            setState(.connected)
            for packet in packets {
                try await send(packet.relayRequest.textFrame())
            }
        } catch {
            connection = nil
            setState(.waitingForRetry)
            throw error
        }
    }

    public func install(_ packet: NostrREQPacket) async throws {
        if connection == nil {
            try await connect()
        }
        guard let connection else { return }
        try await send(packet.relayRequest.textFrame(), connection: connection)
        activeSubscriptions[packet.subscriptionID] = packet
    }

    public func close(subscriptionID: String) async throws {
        guard let connection else {
            activeSubscriptions.removeValue(forKey: subscriptionID)
            return
        }
        try await send(Self.closeFrame(subscriptionID: subscriptionID), connection: connection)
        activeSubscriptions.removeValue(forKey: subscriptionID)
    }

    public func receiveNext() async throws {
        guard let connection else { return }
        let raw = try await connection.receive()
        recordReceived(raw)
        guard let message = NostrRelayMessage.parse(raw) else { return }

        switch message {
        case .event(let subscriptionID, let event):
            guard let packet = activeSubscriptions[subscriptionID],
                  eventValidator.isValid(event),
                  NostrRelayFilterMatcher.matches(event: event, filters: packet.filters)
            else { return }
            emit(.event(relayURL: relayURL, subscriptionID: subscriptionID, event: event))
        case .eose(let subscriptionID):
            guard let packet = activeSubscriptions[subscriptionID] else { return }
            emit(.eose(relayURL: relayURL, subscriptionID: subscriptionID))
            if packet.strategy == .backward {
                try await send(Self.closeFrame(subscriptionID: subscriptionID), connection: connection)
                activeSubscriptions.removeValue(forKey: subscriptionID)
            }
        case .closed(let subscriptionID, let message):
            activeSubscriptions.removeValue(forKey: subscriptionID)
            emit(.closed(relayURL: relayURL, subscriptionID: subscriptionID, message: message))
            if message.lowercased().contains("auth-required") {
                emit(.auth(relayURL: relayURL, challenge: message))
            }
        case .notice(let message):
            emit(.notice(relayURL: relayURL, message: message))
        case .auth(let challenge):
            emit(.auth(relayURL: relayURL, challenge: challenge))
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
        await connection?.close()
        connection = nil
        activeSubscriptions = [:]
        setState(.terminated)
        continuation?.finish()
        continuation = nil
    }

    private func setState(_ state: NostrRelayConnectionState) {
        guard connectionState != state else { return }
        connectionState = state
        emit(.stateChanged(relayURL: relayURL, state: state))
    }

    private func emit(_ packet: NostrRelayRuntimePacket) {
        continuation?.yield(packet)
    }

    private func send(_ textFrame: String) async throws {
        guard let connection else { return }
        try await send(textFrame, connection: connection)
    }

    private func send(_ textFrame: String, connection: any NostrRelayTransportConnection) async throws {
        try await connection.send(textFrame)
        recordSent(textFrame)
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

    private static func closeFrame(subscriptionID: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["CLOSE", subscriptionID], options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? #"["CLOSE",""]"#
    }
}
