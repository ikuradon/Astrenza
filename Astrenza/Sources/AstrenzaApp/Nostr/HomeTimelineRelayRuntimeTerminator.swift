@MainActor
final class HomeTimelineRelayRuntimeTerminator {
    typealias Termination = @MainActor @Sendable () async -> Void
    typealias LatestCompletion = @MainActor @Sendable () async -> Void

    private var task: Task<Void, Never>?
    private var sequence: UInt64 = 0

    var isTerminating: Bool {
        task != nil
    }

    func schedule(
        termination: @escaping Termination,
        onLatestCompletion: @escaping LatestCompletion
    ) {
        sequence &+= 1
        let expectedSequence = sequence
        let previousTask = task
        task = Task { @MainActor [weak self] in
            await previousTask?.value
            await termination()
            guard let self,
                  sequence == expectedSequence
            else { return }
            task = nil
            await onLatestCompletion()
        }
    }
}
