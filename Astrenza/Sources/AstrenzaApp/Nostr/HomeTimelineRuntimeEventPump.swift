import AstrenzaCore

@MainActor
final class HomeTimelineRuntimeEventPump {
    typealias StreamProvider = @MainActor @Sendable () async -> AsyncStream<NostrRelayRuntimePacket>
    typealias SourceValidity = @MainActor @Sendable () -> Bool
    typealias PacketHandler = @MainActor @Sendable (_ packet: NostrRelayRuntimePacket) async -> Void

    private var task: Task<Void, Never>?
    private var sequence: UInt64 = 0
    private var readinessWaiters: [CheckedContinuation<Bool, Never>] = []

    private(set) var isReady = false

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
                await onPacket(packet)
            }
            finish(sequence: expectedSequence)
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
        task = nil
        resolveReadiness(false)
    }

    private func isCurrent(sequence: UInt64) -> Bool {
        self.sequence == sequence
    }

    private func finish(sequence: UInt64) {
        guard isCurrent(sequence: sequence) else { return }
        task = nil
        resolveReadiness(false)
    }

    private func resolveReadiness(_ isReady: Bool) {
        self.isReady = isReady
        let waiters = readinessWaiters
        readinessWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume(returning: isReady) }
    }
}
