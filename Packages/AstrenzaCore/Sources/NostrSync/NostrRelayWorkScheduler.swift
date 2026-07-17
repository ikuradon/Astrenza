import Foundation
import NostrProtocol

public enum NostrRelayWorkPriority: Int, Codable, Comparable, Sendable {
    case maintenance = 0
    case backfill = 100
    case backgroundDependency = 200
    case visibleDependency = 300
    case userInitiated = 400
    case realtime = 500

    public static func < (lhs: NostrRelayWorkPriority, rhs: NostrRelayWorkPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct NostrRelayWorkSchedulerPolicy: Equatable, Sendable {
    public let fallbackMaxSubscriptions: Int?
    public let queueTimeoutMilliseconds: Int

    public init(
        fallbackMaxSubscriptions: Int? = nil,
        queueTimeoutMilliseconds: Int = 7_000
    ) {
        self.fallbackMaxSubscriptions = fallbackMaxSubscriptions.map { max(1, $0) }
        self.queueTimeoutMilliseconds = max(0, queueTimeoutMilliseconds)
    }

    public var queueTimeoutNanoseconds: UInt64? {
        guard queueTimeoutMilliseconds > 0 else { return nil }
        return UInt64(queueTimeoutMilliseconds) * 1_000_000
    }
}

public struct NostrRelayWorkTicket: Hashable, Sendable {
    public let id: UUID
    public let relayURL: NostrRelayURL
    public let subscriptionID: String
    public let priority: NostrRelayWorkPriority

    init(
        id: UUID = UUID(),
        relayURL: NostrRelayURL,
        subscriptionID: String,
        priority: NostrRelayWorkPriority
    ) {
        self.id = id
        self.relayURL = relayURL
        self.subscriptionID = subscriptionID
        self.priority = priority
    }
}

public struct NostrRelayWorkSnapshot: Equatable, Sendable {
    public let relayURL: String
    public let maxSubscriptions: Int?
    public let activeCount: Int
    public let queuedCount: Int
    public let queuedByPriority: [NostrRelayWorkPriority: Int]
    public let activeSubscriptionIDs: [String]
    public let queuedSubscriptionIDs: [String]
}

public enum NostrRelayWorkSchedulerError: Error, Equatable, Sendable {
    case unknownTicket
    case queueTimedOut(relayURL: String, subscriptionID: String)
}

public actor NostrRelayWorkScheduler {
    private struct QueuedWork {
        let ticket: NostrRelayWorkTicket
        let sequence: UInt64
        var continuation: CheckedContinuation<Void, Error>?
    }

    public let policy: NostrRelayWorkSchedulerPolicy
    private var publishedCapacities: [NostrRelayURL: Int] = [:]
    private var activeTickets: [NostrRelayURL: Set<NostrRelayWorkTicket>] = [:]
    private var queuedWork: [NostrRelayURL: [QueuedWork]] = [:]
    private var nextSequence: UInt64 = 0

    public init(policy: NostrRelayWorkSchedulerPolicy = NostrRelayWorkSchedulerPolicy()) {
        self.policy = policy
    }

    public func setPublishedMaxSubscriptions(_ capacity: Int?, for relayURL: NostrRelayURL) {
        publishedCapacities[relayURL] = capacity.map { max(1, $0) }
        drain(relayURL)
    }

    public func enqueue(
        relayURL: NostrRelayURL,
        subscriptionID: String,
        priority: NostrRelayWorkPriority
    ) -> NostrRelayWorkTicket {
        nextSequence &+= 1
        let ticket = NostrRelayWorkTicket(
            relayURL: relayURL,
            subscriptionID: subscriptionID,
            priority: priority
        )
        queuedWork[relayURL, default: []].append(QueuedWork(
            ticket: ticket,
            sequence: nextSequence,
            continuation: nil
        ))
        drain(relayURL)
        return ticket
    }

    public func isActive(_ ticket: NostrRelayWorkTicket) -> Bool {
        activeTickets[ticket.relayURL]?.contains(ticket) == true
    }

    public nonisolated func waitUntilActive(_ ticket: NostrRelayWorkTicket) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await self.registerWaiter(continuation, for: ticket)
                }
            }
        } onCancel: {
            Task {
                await self.release(ticket)
            }
        }
    }

    public nonisolated func waitUntilActiveWithPolicyTimeout(
        _ ticket: NostrRelayWorkTicket
    ) async throws {
        guard let timeoutNanoseconds = policy.queueTimeoutNanoseconds else {
            try await waitUntilActive(ticket)
            return
        }

        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            await self.failQueuedWork(
                ticket,
                error: .queueTimedOut(
                    relayURL: ticket.relayURL.rawValue,
                    subscriptionID: ticket.subscriptionID
                )
            )
        }
        defer { timeoutTask.cancel() }
        try await waitUntilActive(ticket)
    }

    public func release(_ ticket: NostrRelayWorkTicket) {
        let relayURL = ticket.relayURL
        if activeTickets[relayURL]?.remove(ticket) != nil,
           activeTickets[relayURL]?.isEmpty == true {
            activeTickets[relayURL] = nil
        }

        if let index = queuedWork[relayURL]?.firstIndex(where: { $0.ticket == ticket }) {
            let queued = queuedWork[relayURL]?.remove(at: index)
            queued?.continuation?.resume(throwing: CancellationError())
            if queuedWork[relayURL]?.isEmpty == true {
                queuedWork[relayURL] = nil
            }
        }
        drain(relayURL)
    }

    public func snapshot(for relayURL: NostrRelayURL) -> NostrRelayWorkSnapshot {
        let queued = (queuedWork[relayURL] ?? []).sorted { lhs, rhs in
            if lhs.ticket.priority == rhs.ticket.priority {
                return lhs.sequence < rhs.sequence
            }
            return lhs.ticket.priority > rhs.ticket.priority
        }
        return NostrRelayWorkSnapshot(
            relayURL: relayURL.rawValue,
            maxSubscriptions: effectiveCapacity(for: relayURL),
            activeCount: activeTickets[relayURL]?.count ?? 0,
            queuedCount: queued.count,
            queuedByPriority: Dictionary(grouping: queued, by: \.ticket.priority)
                .mapValues(\.count),
            activeSubscriptionIDs: (activeTickets[relayURL] ?? [])
                .map(\.subscriptionID)
                .sorted(),
            queuedSubscriptionIDs: queued.map(\.ticket.subscriptionID)
        )
    }

    public func cancelAll() {
        let continuations = queuedWork.values
            .flatMap { $0 }
            .compactMap(\.continuation)
        activeTickets.removeAll(keepingCapacity: false)
        queuedWork.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume(throwing: CancellationError()) }
    }

    private func registerWaiter(
        _ continuation: CheckedContinuation<Void, Error>,
        for ticket: NostrRelayWorkTicket
    ) {
        if activeTickets[ticket.relayURL]?.contains(ticket) == true {
            continuation.resume()
            return
        }
        guard let index = queuedWork[ticket.relayURL]?.firstIndex(where: {
            $0.ticket == ticket
        }) else {
            continuation.resume(throwing: NostrRelayWorkSchedulerError.unknownTicket)
            return
        }
        queuedWork[ticket.relayURL]?[index].continuation = continuation
        drain(ticket.relayURL)
    }

    private func failQueuedWork(
        _ ticket: NostrRelayWorkTicket,
        error: NostrRelayWorkSchedulerError
    ) {
        let relayURL = ticket.relayURL
        guard let index = queuedWork[relayURL]?.firstIndex(where: { $0.ticket == ticket }) else {
            return
        }
        let queued = queuedWork[relayURL]?.remove(at: index)
        queued?.continuation?.resume(throwing: error)
        if queuedWork[relayURL]?.isEmpty == true {
            queuedWork[relayURL] = nil
        }
        drain(relayURL)
    }

    private func drain(_ relayURL: NostrRelayURL) {
        let capacity = effectiveCapacity(for: relayURL) ?? Int.max
        let activeCount = activeTickets[relayURL]?.count ?? 0
        guard activeCount < capacity, var queue = queuedWork[relayURL], !queue.isEmpty else {
            return
        }

        queue.sort { lhs, rhs in
            if lhs.ticket.priority == rhs.ticket.priority {
                return lhs.sequence < rhs.sequence
            }
            return lhs.ticket.priority > rhs.ticket.priority
        }

        let activationCount = min(capacity - activeCount, queue.count)
        let activating = Array(queue.prefix(activationCount))
        queue.removeFirst(activationCount)
        queuedWork[relayURL] = queue.isEmpty ? nil : queue
        for work in activating {
            activeTickets[relayURL, default: []].insert(work.ticket)
            work.continuation?.resume()
        }
    }

    private func effectiveCapacity(for relayURL: NostrRelayURL) -> Int? {
        publishedCapacities[relayURL] ?? policy.fallbackMaxSubscriptions
    }
}
