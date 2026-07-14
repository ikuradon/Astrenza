import AstrenzaCore
import Foundation

enum HomeTimelineGapPersistenceOutcome: Equatable, Sendable {
    case verifiedComplete(resolveFailure: String?)
    case indeterminate
    case recovered([NostrEvent])
    case recoveryFailed(String)
}

struct HomeTimelineBackfillPersistence: Sendable {
    typealias Now = @Sendable () -> Int

    private let eventStore: NostrEventStore?
    private let now: Now

    init(
        eventStore: NostrEventStore?,
        now: @escaping Now = { Int(Date().timeIntervalSince1970) }
    ) {
        self.eventStore = eventStore
        self.now = now
    }

    @discardableResult
    func markOlderPageBoundaryGap(
        request: PendingBackwardRequest,
        definition: NostrFeedDefinitionRecord
    ) throws -> Bool {
        guard let anchorEventID = request.olderAnchorPostID,
              let newestReceivedEventID = newestReceivedTimelineEventID(in: request)
        else { return false }
        try eventStore?.markFeedGap(
            feedID: definition.feedID,
            revision: definition.revision,
            newerEventID: anchorEventID,
            olderEventID: newestReceivedEventID,
            state: .unresolved,
            sourceRequestID: request.sourceRequestIDs.last,
            at: now()
        )
        return true
    }

    func markGapUnresolved(
        _ gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) {
        try? eventStore?.markFeedGap(
            feedID: context.feedID,
            revision: context.revision,
            newerEventID: gap.newerPostID,
            olderEventID: gap.olderPostID,
            state: .unresolved,
            at: now()
        )
    }

    func apply(
        _ result: HomeTimelineGapReconciliationResult,
        gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) -> HomeTimelineGapPersistenceOutcome {
        switch result {
        case .verifiedComplete:
            do {
                try eventStore?.resolveFeedGap(
                    feedID: context.feedID,
                    revision: context.revision,
                    newerEventID: gap.newerPostID,
                    olderEventID: gap.olderPostID,
                    at: now()
                )
                return .verifiedComplete(resolveFailure: nil)
            } catch {
                return .verifiedComplete(resolveFailure: error.localizedDescription)
            }
        case .indeterminate:
            markGapUnresolved(gap, context: context)
            return .indeterminate
        case .recovered(let recoveredEvents):
            let scopedEvents = recoveredEvents.filter(context.includes)
            let insertedAt = now()
            let memberships = HomeFeedProjectionBuilder.memberships(
                events: scopedEvents,
                feedID: context.feedID,
                feedRevision: context.revision,
                reason: "gap-negentropy",
                insertedAt: insertedAt
            )
            let membershipSources = HomeFeedProjectionBuilder.membershipSources(
                events: scopedEvents,
                feedID: context.feedID,
                feedRevision: context.revision,
                reason: "gap-negentropy",
                insertedAt: insertedAt
            )
            do {
                try eventStore?.ingest(
                    events: scopedEvents,
                    eventSources: [],
                    feedMemberships: memberships,
                    feedMembershipSources: membershipSources,
                    receivedAt: insertedAt
                )
                markGapUnresolved(gap, context: context)
                return .recovered(scopedEvents)
            } catch {
                return .recoveryFailed(error.localizedDescription)
            }
        }
    }

    private func newestReceivedTimelineEventID(
        in request: PendingBackwardRequest
    ) -> String? {
        guard let eventStore else { return nil }
        let uniqueEventIDs = Array(Set(request.receivedTimelineEventIDs))
        guard !uniqueEventIDs.isEmpty,
              let events = try? eventStore.events(ids: uniqueEventIDs)
        else { return nil }
        return events.max { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }?.id
    }
}
