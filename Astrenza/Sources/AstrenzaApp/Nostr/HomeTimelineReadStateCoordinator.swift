import AstrenzaCore
import Foundation

struct HomeTimelineReadPosition: Equatable, Sendable {
    let postID: String
    let createdAt: Int
}

struct HomeTimelineReadBoundaryWrite: Sendable {
    let scopeID: String
    let feedID: String
    let boundary: NostrTimelineEntryCursor?
    let updatedAt: Int
}

protocol HomeTimelineReadStatePersisting: Actor {
    func restoredReadState(feedID: String) throws -> NostrFeedReadStateRecord?

    func saveReadBoundary(
        feedID: String,
        boundary: NostrTimelineEntryCursor?,
        updatedAt: Int
    ) throws
}

extension HomeTimelinePersistenceWorker: HomeTimelineReadStatePersisting {}

@MainActor
final class HomeTimelineReadStateCoordinator {
    private let persistenceWorker: (any HomeTimelineReadStatePersisting)?
    private let readBoundaryDelayNanoseconds: UInt64
    private let persistenceRetryDelayNanoseconds: UInt64

    private var readBoundaryTask: Task<Void, Never>?
    private var pendingReadBoundaryWrite: HomeTimelineReadBoundaryWrite?
    private var scopeID: String?
    private var scopeGeneration: UInt64 = 0
    private var readBoundarySequence: UInt64 = 0

    var hasPendingReadBoundaryWrite: Bool {
        pendingReadBoundaryWrite != nil
    }

    init(
        persistenceWorker: (any HomeTimelineReadStatePersisting)?,
        readBoundaryDelayNanoseconds: UInt64 = 500_000_000,
        persistenceRetryDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.persistenceWorker = persistenceWorker
        self.readBoundaryDelayNanoseconds = readBoundaryDelayNanoseconds
        self.persistenceRetryDelayNanoseconds = persistenceRetryDelayNanoseconds
    }

    func restoredReadBoundaryPostID(
        feedID: String,
        positions: [HomeTimelineReadPosition]
    ) async -> String? {
        guard let persistenceWorker,
              let state = try? await persistenceWorker.restoredReadState(
                  feedID: feedID
              ),
              let cursor = state.readBoundary
        else { return nil }
        if positions.contains(where: { $0.postID == cursor.eventID }) {
            return cursor.eventID
        }
        return positions.first { position in
            position.createdAt < cursor.sortTimestamp ||
                (position.createdAt == cursor.sortTimestamp && position.postID >= cursor.eventID)
        }?.postID
    }

    @discardableResult
    func scheduleReadBoundarySave(_ write: HomeTimelineReadBoundaryWrite) -> Bool {
        guard persistenceWorker != nil else { return false }
        activateScope(write.scopeID)

        pendingReadBoundaryWrite = write
        readBoundarySequence &+= 1
        let expectedSequence = readBoundarySequence
        let expectedGeneration = scopeGeneration
        schedulePersistence(
            delayNanoseconds: readBoundaryDelayNanoseconds,
            expectedScopeGeneration: expectedGeneration,
            expectedSequence: expectedSequence
        )
        return true
    }

    func endSession(flushing readBoundaryWrite: HomeTimelineReadBoundaryWrite?) {
        let effectiveReadBoundaryWrite = readBoundaryWrite ?? pendingReadBoundaryWrite
        discardPendingWrites()
        persistDetached(effectiveReadBoundaryWrite)
    }

    private func activateScope(_ nextScopeID: String) {
        guard scopeID != nextScopeID else { return }
        let previousWrite = pendingReadBoundaryWrite
        discardPendingWrites()
        persistDetached(previousWrite)
        scopeID = nextScopeID
    }

    private func discardPendingWrites() {
        scopeGeneration &+= 1
        readBoundarySequence &+= 1
        readBoundaryTask?.cancel()
        readBoundaryTask = nil
        pendingReadBoundaryWrite = nil
        scopeID = nil
    }

    private func persistPendingReadBoundaryWrite(
        expectedScopeGeneration: UInt64,
        expectedSequence: UInt64
    ) async {
        guard scopeGeneration == expectedScopeGeneration,
              readBoundarySequence == expectedSequence,
              let write = pendingReadBoundaryWrite,
              write.scopeID == scopeID,
              let persistenceWorker
        else { return }
        readBoundaryTask = nil
        do {
            try await persistenceWorker.saveReadBoundary(
                feedID: write.feedID,
                boundary: write.boundary,
                updatedAt: write.updatedAt
            )
        } catch {
            guard scopeGeneration == expectedScopeGeneration,
                  readBoundarySequence == expectedSequence,
                  pendingReadBoundaryWrite != nil
            else { return }
            schedulePersistence(
                delayNanoseconds: persistenceRetryDelayNanoseconds,
                expectedScopeGeneration: expectedScopeGeneration,
                expectedSequence: expectedSequence
            )
            return
        }
        guard scopeGeneration == expectedScopeGeneration,
              readBoundarySequence == expectedSequence
        else { return }
        pendingReadBoundaryWrite = nil
    }

    private func schedulePersistence(
        delayNanoseconds: UInt64,
        expectedScopeGeneration: UInt64,
        expectedSequence: UInt64
    ) {
        readBoundaryTask?.cancel()
        readBoundaryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            await self?.persistPendingReadBoundaryWrite(
                expectedScopeGeneration: expectedScopeGeneration,
                expectedSequence: expectedSequence
            )
        }
    }

    private func persistDetached(
        _ readBoundaryWrite: HomeTimelineReadBoundaryWrite?
    ) {
        guard let persistenceWorker, let readBoundaryWrite else { return }
        let retryDelayNanoseconds = persistenceRetryDelayNanoseconds
        Task.detached(priority: .utility) {
            for attempt in 0..<3 {
                do {
                    try await persistenceWorker.saveReadBoundary(
                        feedID: readBoundaryWrite.feedID,
                        boundary: readBoundaryWrite.boundary,
                        updatedAt: readBoundaryWrite.updatedAt
                    )
                    return
                } catch {
                    guard attempt < 2 else { return }
                    try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
                }
            }
        }
    }
}
