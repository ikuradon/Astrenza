import Foundation

@MainActor
final class NostrProjectionRefreshCoordinator {
    private let delayNanoseconds: UInt64
    private var pendingWorkItem: DispatchWorkItem?
    private var pendingGeneration = 0

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func schedule(_ operation: @escaping @MainActor () -> Void) {
        schedule(delayNanoseconds: delayNanoseconds, operation)
    }

    func schedule(delayNanoseconds: UInt64, _ operation: @escaping @MainActor () -> Void) {
        guard pendingWorkItem == nil else { return }
        pendingGeneration += 1
        let generation = pendingGeneration
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.complete(generation: generation, operation)
            }
        }
        pendingWorkItem = workItem
        let delay = DispatchTimeInterval.nanoseconds(Int(delayNanoseconds))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func flush(_ operation: @escaping @MainActor () -> Void) {
        cancel()
        operation()
    }

    func cancel() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        pendingGeneration += 1
    }

    private func complete(generation: Int, _ operation: @escaping @MainActor () -> Void) {
        guard pendingGeneration == generation, pendingWorkItem != nil else { return }
        pendingWorkItem = nil
        operation()
    }
}
