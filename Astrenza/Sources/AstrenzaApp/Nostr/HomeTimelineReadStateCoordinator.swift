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
        readBoundaryDelayNanoseconds: UInt64 = 500_000_000
    ) {
        self.persistenceWorker = persistenceWorker
        self.readBoundaryDelayNanoseconds = readBoundaryDelayNanoseconds
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
        readBoundaryTask?.cancel()
        readBoundaryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.readBoundaryDelayNanoseconds ?? 0)
            } catch {
                return
            }
            await self?.persistPendingReadBoundaryWrite(
                expectedScopeGeneration: expectedGeneration,
                expectedSequence: expectedSequence
            )
        }
        return true
    }

    func endSession(flushing readBoundaryWrite: HomeTimelineReadBoundaryWrite?) {
        let effectiveReadBoundaryWrite = readBoundaryWrite ?? pendingReadBoundaryWrite
        discardPendingWrites()
        persistDetached(effectiveReadBoundaryWrite)
    }

    private func activateScope(_ nextScopeID: String) {
        guard scopeID != nextScopeID else { return }
        discardPendingWrites()
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
        pendingReadBoundaryWrite = nil
        try? await persistenceWorker.saveReadBoundary(
            feedID: write.feedID,
            boundary: write.boundary,
            updatedAt: write.updatedAt
        )
    }

    private func persistDetached(
        _ readBoundaryWrite: HomeTimelineReadBoundaryWrite?
    ) {
        guard let persistenceWorker, let readBoundaryWrite else { return }
        Task {
            try? await persistenceWorker.saveReadBoundary(
                feedID: readBoundaryWrite.feedID,
                boundary: readBoundaryWrite.boundary,
                updatedAt: readBoundaryWrite.updatedAt
            )
        }
    }
}
