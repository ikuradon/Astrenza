import Foundation

@MainActor
final class NostrProjectionRefreshCoordinator {
    private let delayNanoseconds: UInt64
    private var pendingTask: Task<Void, Never>?
    private var pendingGeneration = 0

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func schedule(_ operation: @escaping @MainActor () -> Void) {
        guard pendingTask == nil else { return }
        let delayNanoseconds = delayNanoseconds
        pendingGeneration += 1
        let generation = pendingGeneration
        pendingTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.complete(generation: generation, operation)
        }
    }

    func flush(_ operation: @escaping @MainActor () -> Void) {
        cancel()
        operation()
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingGeneration += 1
    }

    private func complete(generation: Int, _ operation: @escaping @MainActor () -> Void) {
        guard pendingGeneration == generation, pendingTask != nil else { return }
        pendingTask = nil
        operation()
    }
}
