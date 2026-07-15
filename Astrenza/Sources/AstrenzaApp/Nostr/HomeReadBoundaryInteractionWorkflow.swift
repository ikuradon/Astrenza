import AstrenzaCore
import Foundation

@MainActor
protocol HomeTimelineReadStateCoordinating: AnyObject {
    func restoredReadBoundaryPostID(
        feedID: String,
        positions: [HomeTimelineReadPosition]
    ) async -> String?

    @discardableResult
    func scheduleReadBoundarySave(
        _ write: HomeTimelineReadBoundaryWrite
    ) -> Bool
}

extension HomeTimelineReadStateCoordinator: HomeTimelineReadStateCoordinating {}

@MainActor
final class HomeReadBoundaryInteractionWorkflow {
    typealias TimestampProvider = @MainActor @Sendable () -> Int

    private let feedIdentity: any HomeFeedIdentityResolving
    private let readState: any HomeTimelineReadStateCoordinating
    private let timestamp: TimestampProvider

    init(
        feedIdentity: any HomeFeedIdentityResolving,
        readState: any HomeTimelineReadStateCoordinating,
        timestamp: @escaping TimestampProvider = {
            Int(Date().timeIntervalSince1970)
        }
    ) {
        self.feedIdentity = feedIdentity
        self.readState = readState
        self.timestamp = timestamp
    }

    func restoredReadBoundaryPostID(
        accountID: String,
        positions: [HomeTimelineReadPosition]
    ) async -> String? {
        guard let feedID = feedIdentity.feedID(accountID: accountID) else {
            return nil
        }
        return await readState.restoredReadBoundaryPostID(
            feedID: feedID,
            positions: positions
        )
    }

    func readBoundaryWrite(
        accountID: String,
        boundaryEvent: NostrEvent?
    ) -> HomeTimelineReadBoundaryWrite? {
        guard let feedID = feedIdentity.feedID(accountID: accountID) else {
            return nil
        }
        return HomeTimelineReadBoundaryWrite(
            scopeID: accountID,
            feedID: feedID,
            boundary: boundaryEvent.map {
                NostrTimelineEntryCursor(
                    sortTimestamp: $0.createdAt,
                    eventID: $0.id
                )
            },
            updatedAt: timestamp()
        )
    }

    @discardableResult
    func scheduleReadBoundarySave(
        accountID: String,
        boundaryEvent: NostrEvent?
    ) -> Bool {
        guard let write = readBoundaryWrite(
            accountID: accountID,
            boundaryEvent: boundaryEvent
        ) else { return false }
        return readState.scheduleReadBoundarySave(write)
    }
}
