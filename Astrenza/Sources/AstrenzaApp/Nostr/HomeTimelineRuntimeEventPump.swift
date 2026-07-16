import AstrenzaCore

@MainActor
final class HomeTimelineRuntimeEventPump {
    typealias StreamProvider = @MainActor @Sendable () async -> AsyncStream<NostrRelayRuntimePacket>
    typealias SourceValidity = @MainActor @Sendable () -> Bool
    typealias PacketHandler = @MainActor @Sendable (_ packets: [NostrRelayRuntimePacket]) async -> Void

    struct Policy: Equatable, Sendable {
        let maxEventCount: Int
        let maxDelayNanoseconds: UInt64

        static let `default` = Policy(
            maxEventCount: 32,
            maxDelayNanoseconds: 8_000_000
        )
    }

    private var task: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var sequence: UInt64 = 0
    private var readinessWaiters: [CheckedContinuation<Bool, Never>] = []
    private var pendingEvents: [NostrRelayRuntimePacket] = []
    private var pendingBatches: [[NostrRelayRuntimePacket]] = []
    private var packetHandler: PacketHandler?
    private var sourceValidity: SourceValidity?
    private var inputFinished = false
    private let policy: Policy

    private(set) var isReady = false

    init(policy: Policy = .default) {
        self.policy = policy
    }

    var isRunning: Bool {
        task != nil
    }

    var pendingReadinessWaiterCount: Int {
        readinessWaiters.count
    }

    @discardableResult
    func start(
        stream: @escaping StreamProvider,
        isSourceCurrent: @escaping SourceValidity,
        onPacket: @escaping PacketHandler
    ) -> Bool {
        guard task == nil else { return false }
        sequence &+= 1
        let expectedSequence = sequence
        resolveReadiness(false)
        inputFinished = false
        packetHandler = onPacket
        sourceValidity = isSourceCurrent
        task = Task { @MainActor [weak self] in
            let packets = await stream()
            guard let self else { return }
            guard !Task.isCancelled,
                  isCurrent(sequence: expectedSequence),
                  isSourceCurrent()
            else {
                finish(sequence: expectedSequence)
                return
            }

            resolveReadiness(true)
            for await packet in packets {
                guard !Task.isCancelled,
                      isCurrent(sequence: expectedSequence),
                      isSourceCurrent()
                else { break }
                enqueue(packet, sequence: expectedSequence)
            }
            finishInput(sequence: expectedSequence)
        }
        return true
    }

    func waitUntilReady() async -> Bool {
        if isReady { return true }
        guard task != nil, !Task.isCancelled else { return false }
        let readiness = await withCheckedContinuation { continuation in
            if isReady {
                continuation.resume(returning: true)
            } else if task != nil {
                readinessWaiters.append(continuation)
            } else {
                continuation.resume(returning: false)
            }
        }
        return readiness && !Task.isCancelled
    }

    func cancel() {
        sequence &+= 1
        task?.cancel()
        deliveryTask?.cancel()
        flushTask?.cancel()
        task = nil
        deliveryTask = nil
        flushTask = nil
        pendingEvents.removeAll(keepingCapacity: true)
        pendingBatches.removeAll(keepingCapacity: true)
        packetHandler = nil
        sourceValidity = nil
        inputFinished = false
        resolveReadiness(false)
    }

    private func isCurrent(sequence: UInt64) -> Bool {
        self.sequence == sequence
    }

    private func finish(sequence: UInt64) {
        guard isCurrent(sequence: sequence) else { return }
        task?.cancel()
        task = nil
        deliveryTask = nil
        flushTask = nil
        packetHandler = nil
        sourceValidity = nil
        inputFinished = false
        resolveReadiness(false)
    }

    private func enqueue(
        _ packet: NostrRelayRuntimePacket,
        sequence: UInt64
    ) {
        if case .event = packet {
            pendingEvents.append(packet)
            if pendingEvents.count >= policy.maxEventCount {
                flushPendingEvents(sequence: sequence)
            } else {
                scheduleFlush(sequence: sequence)
            }
            return
        }

        flushPendingEvents(sequence: sequence)
        enqueueBatch([packet], sequence: sequence)
    }

    private func scheduleFlush(sequence: UInt64) {
        guard flushTask == nil else { return }
        let delay = policy.maxDelayNanoseconds
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.flushTask = nil
            self?.flushPendingEvents(sequence: sequence)
        }
    }

    private func flushPendingEvents(sequence: UInt64) {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingEvents.isEmpty else { return }
        let batch = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        enqueueBatch(batch, sequence: sequence)
    }

    private func enqueueBatch(
        _ batch: [NostrRelayRuntimePacket],
        sequence: UInt64
    ) {
        guard !batch.isEmpty else { return }
        pendingBatches.append(batch)
        guard deliveryTask == nil else { return }
        deliveryTask = Task { @MainActor [weak self] in
            await self?.drainBatches(sequence: sequence)
        }
    }

    private func drainBatches(sequence: UInt64) async {
        while isCurrent(sequence: sequence), !Task.isCancelled,
              sourceValidity?() == true, !pendingBatches.isEmpty {
            let batch = pendingBatches.removeFirst()
            guard let packetHandler else { break }
            await packetHandler(batch)
        }

        guard isCurrent(sequence: sequence) else { return }
        deliveryTask = nil
        if sourceValidity?() != true {
            pendingBatches.removeAll(keepingCapacity: true)
            pendingEvents.removeAll(keepingCapacity: true)
            inputFinished = true
        }
        if inputFinished {
            finish(sequence: sequence)
        }
    }

    private func finishInput(sequence: UInt64) {
        guard isCurrent(sequence: sequence) else { return }
        inputFinished = true
        flushPendingEvents(sequence: sequence)
        if deliveryTask == nil {
            finish(sequence: sequence)
        }
    }

    private func resolveReadiness(_ isReady: Bool) {
        self.isReady = isReady
        let waiters = readinessWaiters
        readinessWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume(returning: isReady) }
    }
}
