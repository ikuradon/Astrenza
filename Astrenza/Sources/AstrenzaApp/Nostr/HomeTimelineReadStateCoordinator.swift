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

private struct HomeTimelineViewportWrite: Sendable {
    let scopeID: String
    let feedID: String
    let anchorEventID: String?
    let anchorOffset: Double
    let updatedAt: Int
}

protocol HomeTimelineReadStatePersisting: Actor {
    func restoredReadState(feedID: String) throws -> NostrFeedReadStateRecord?

    func saveViewportState(
        feedID: String,
        anchorEventID: String?,
        anchorOffset: Double,
        updatedAt: Int
    ) throws

    func saveReadBoundary(
        feedID: String,
        boundary: NostrTimelineEntryCursor?,
        updatedAt: Int
    ) throws
}

extension HomeTimelinePersistenceWorker: HomeTimelineReadStatePersisting {}

@MainActor
final class HomeTimelineReadStateCoordinator {
    private let eventStore: NostrEventStore?
    private let persistenceWorker: (any HomeTimelineReadStatePersisting)?
    private let viewportDelayNanoseconds: UInt64
    private let readBoundaryDelayNanoseconds: UInt64

    private var viewportTask: Task<Void, Never>?
    private var readBoundaryTask: Task<Void, Never>?
    private var pendingViewportWrite: HomeTimelineViewportWrite?
    private var pendingReadBoundaryWrite: HomeTimelineReadBoundaryWrite?
    private var scopeID: String?
    private var scopeGeneration: UInt64 = 0
    private var viewportSequence: UInt64 = 0
    private var readBoundarySequence: UInt64 = 0

    var hasPendingViewportWrite: Bool {
        pendingViewportWrite != nil
    }

    var hasPendingReadBoundaryWrite: Bool {
        pendingReadBoundaryWrite != nil
    }

    init(
        eventStore: NostrEventStore?,
        persistenceWorker: (any HomeTimelineReadStatePersisting)?,
        viewportDelayNanoseconds: UInt64 = 600_000_000,
        readBoundaryDelayNanoseconds: UInt64 = 500_000_000
    ) {
        self.eventStore = eventStore
        self.persistenceWorker = persistenceWorker
        self.viewportDelayNanoseconds = viewportDelayNanoseconds
        self.readBoundaryDelayNanoseconds = readBoundaryDelayNanoseconds
    }

    func restoredViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        guard timelineKey == "home",
              let eventStore,
              let state = try? eventStore.feedReadState(
                feedID: HomeFeedProjectionBuilder.feedID(accountID: accountID)
              ),
              let anchorEventID = state.viewportAnchorEventID
        else { return nil }
        return TimelineViewportState(
            accountID: accountID,
            timelineKey: timelineKey,
            anchorPostID: anchorEventID,
            anchorOffset: state.viewportAnchorOffset,
            contentOffset: 0,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(state.updatedAt))
        )
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
    func scheduleViewportState(
        _ state: TimelineViewportState,
        feedID: String,
        scopeID: String
    ) -> Bool {
        guard persistenceWorker != nil,
              state.timelineKey == "home",
              state.accountID == scopeID
        else { return false }
        activateScope(scopeID)

        pendingViewportWrite = HomeTimelineViewportWrite(
            scopeID: scopeID,
            feedID: feedID,
            anchorEventID: state.anchorPostID,
            anchorOffset: Double(state.anchorOffset),
            updatedAt: Int(state.updatedAt.timeIntervalSince1970)
        )
        viewportSequence &+= 1
        let expectedSequence = viewportSequence
        let expectedGeneration = scopeGeneration
        viewportTask?.cancel()
        viewportTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.viewportDelayNanoseconds ?? 0)
            } catch {
                return
            }
            await self?.persistPendingViewportWrite(
                expectedScopeGeneration: expectedGeneration,
                expectedSequence: expectedSequence
            )
        }
        return true
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

    func flushPendingViewportWrite() {
        viewportSequence &+= 1
        viewportTask?.cancel()
        viewportTask = nil
        let write = pendingViewportWrite
        pendingViewportWrite = nil
        persistDetached(viewportWrite: write, readBoundaryWrite: nil)
    }

    func endSession(flushing readBoundaryWrite: HomeTimelineReadBoundaryWrite?) {
        let viewportWrite = pendingViewportWrite
        let effectiveReadBoundaryWrite = readBoundaryWrite ?? pendingReadBoundaryWrite
        discardPendingWrites()
        persistDetached(
            viewportWrite: viewportWrite,
            readBoundaryWrite: effectiveReadBoundaryWrite
        )
    }

    private func activateScope(_ nextScopeID: String) {
        guard scopeID != nextScopeID else { return }
        discardPendingWrites()
        scopeID = nextScopeID
    }

    private func discardPendingWrites() {
        scopeGeneration &+= 1
        viewportSequence &+= 1
        readBoundarySequence &+= 1
        viewportTask?.cancel()
        readBoundaryTask?.cancel()
        viewportTask = nil
        readBoundaryTask = nil
        pendingViewportWrite = nil
        pendingReadBoundaryWrite = nil
        scopeID = nil
    }

    private func persistPendingViewportWrite(
        expectedScopeGeneration: UInt64,
        expectedSequence: UInt64
    ) async {
        guard scopeGeneration == expectedScopeGeneration,
              viewportSequence == expectedSequence,
              let write = pendingViewportWrite,
              write.scopeID == scopeID,
              let persistenceWorker
        else { return }
        viewportTask = nil
        pendingViewportWrite = nil
        try? await persistenceWorker.saveViewportState(
            feedID: write.feedID,
            anchorEventID: write.anchorEventID,
            anchorOffset: write.anchorOffset,
            updatedAt: write.updatedAt
        )
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
        viewportWrite: HomeTimelineViewportWrite?,
        readBoundaryWrite: HomeTimelineReadBoundaryWrite?
    ) {
        guard let persistenceWorker,
              viewportWrite != nil || readBoundaryWrite != nil
        else { return }
        Task {
            if let viewportWrite {
                try? await persistenceWorker.saveViewportState(
                    feedID: viewportWrite.feedID,
                    anchorEventID: viewportWrite.anchorEventID,
                    anchorOffset: viewportWrite.anchorOffset,
                    updatedAt: viewportWrite.updatedAt
                )
            }
            if let readBoundaryWrite {
                try? await persistenceWorker.saveReadBoundary(
                    feedID: readBoundaryWrite.feedID,
                    boundary: readBoundaryWrite.boundary,
                    updatedAt: readBoundaryWrite.updatedAt
                )
            }
        }
    }
}
