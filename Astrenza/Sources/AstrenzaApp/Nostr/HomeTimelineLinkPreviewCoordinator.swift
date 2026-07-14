import AstrenzaCore
import Foundation

@MainActor
final class HomeTimelineLinkPreviewCoordinator {
    typealias UpdateHandler = @MainActor () -> Void
    typealias FailureHandler = @MainActor (_ message: String) -> Void

    private let eventStore: NostrEventStore?
    private let resolvePreview: (@Sendable (NostrLinkPreviewRecord) async -> NostrLinkPreviewRecord)?
    private let batchLimit: Int

    private var resolutionTask: Task<Void, Never>?
    private var inFlightURLs = Set<String>()
    private var scopeID: String?
    private var generation: UInt64 = 0

    var hasActiveResolution: Bool {
        resolutionTask != nil
    }

    var inFlightCount: Int {
        inFlightURLs.count
    }

    init(
        eventStore: NostrEventStore?,
        resolver: NostrLinkPreviewResolver?,
        batchLimit: Int = 6
    ) {
        self.eventStore = eventStore
        if let resolver {
            self.resolvePreview = { preview in
                await resolver.resolve(preview)
            }
        } else {
            self.resolvePreview = nil
        }
        self.batchLimit = max(1, batchLimit)
    }

    func reset() {
        generation &+= 1
        resolutionTask?.cancel()
        resolutionTask = nil
        inFlightURLs.removeAll(keepingCapacity: true)
        scopeID = nil
    }

    @discardableResult
    func schedule(
        scopeID: String,
        policy: NostrSyncPolicy,
        didUpdate: @escaping UpdateHandler,
        didFail: @escaping FailureHandler
    ) -> Bool {
        if self.scopeID != scopeID {
            reset()
            self.scopeID = scopeID
        }
        return beginNextBatch(
            scopeID: scopeID,
            policy: policy,
            excludedURLs: [],
            didUpdate: didUpdate,
            didFail: didFail
        )
    }

    @discardableResult
    private func beginNextBatch(
        scopeID: String,
        policy: NostrSyncPolicy,
        excludedURLs: Set<String>,
        didUpdate: @escaping UpdateHandler,
        didFail: @escaping FailureHandler
    ) -> Bool {
        guard resolutionTask == nil,
              let eventStore,
              let resolvePreview,
              NostrContentAttachmentClassifier.linkPreviewFetchMode(for: policy) != .tapRequired
        else { return false }

        let previews = ((try? eventStore.unresolvedLinkPreviews(
            limit: batchLimit + excludedURLs.count
        )) ?? [])
            .filter { !excludedURLs.contains($0.normalizedURL) }
            .prefix(batchLimit)
            .filter { inFlightURLs.insert($0.normalizedURL).inserted }
        guard !previews.isEmpty else { return false }

        let expectedGeneration = generation
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            var persistedCount = 0
            var persistenceFailures: [(url: String, message: String)] = []

            for preview in previews {
                guard !Task.isCancelled,
                      generation == expectedGeneration,
                      self.scopeID == scopeID
                else { return }

                let resolved = await resolvePreview(preview)
                guard !Task.isCancelled,
                      generation == expectedGeneration,
                      self.scopeID == scopeID
                else { return }

                do {
                    try eventStore.saveLinkPreview(resolved)
                    persistedCount += 1
                } catch {
                    persistenceFailures.append((
                        url: preview.normalizedURL,
                        message: error.localizedDescription
                    ))
                }
            }

            guard !Task.isCancelled,
                  generation == expectedGeneration,
                  self.scopeID == scopeID
            else { return }

            previews.forEach { inFlightURLs.remove($0.normalizedURL) }
            resolutionTask = nil
            persistenceFailures.forEach { failure in
                didFail("\(failure.url): \(failure.message)")
            }
            if persistedCount > 0 {
                didUpdate()
            }

            let nextExcludedURLs = excludedURLs.union(persistenceFailures.map(\.url))
            beginNextBatch(
                scopeID: scopeID,
                policy: policy,
                excludedURLs: nextExcludedURLs,
                didUpdate: didUpdate,
                didFail: didFail
            )
        }
        return true
    }
}
