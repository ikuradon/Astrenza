@MainActor
final class HomeTimelineBackwardRequestRegistry {
    private var requestsByGroupID: [String: PendingBackwardRequest] = [:]
    private var activeGapReconciliationIDs = Set<String>()

    var requestCount: Int {
        requestsByGroupID.count
    }

    var hasRequests: Bool {
        !requestsByGroupID.isEmpty
    }

    var hasOlderPageRequest: Bool {
        requestsByGroupID.values.contains(where: \.isOlderPage)
    }

    var hasGapWork: Bool {
        !activeGapReconciliationIDs.isEmpty ||
            requestsByGroupID.values.contains(where: { $0.gap != nil })
    }

    var activeGapReconciliationCount: Int {
        activeGapReconciliationIDs.count
    }

    func reset() {
        requestsByGroupID.removeAll()
        activeGapReconciliationIDs.removeAll()
    }

    func registerOlderPage(
        groupID: String,
        context: HomeFeedRuntimeContext,
        anchorEventID: String?
    ) {
        requestsByGroupID[groupID] = PendingBackwardRequest(
            feedContext: context,
            isOlderPage: true,
            olderAnchorPostID: anchorEventID
        )
    }

    func registerGap(
        groupID: String,
        context: HomeFeedRuntimeContext,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    ) {
        requestsByGroupID[groupID] = PendingBackwardRequest(
            feedContext: context,
            gap: PendingGapBackfill(
                newerPostID: newerEventID,
                olderPostID: olderEventID,
                direction: direction
            )
        )
    }

    func request(for key: String) -> PendingBackwardRequest? {
        requestsByGroupID[key]
    }

    func key(for subscriptionID: String) -> String? {
        if let exactOrPrefixed = requestsByGroupID.first(where: { entry in
            subscriptionID == entry.key || subscriptionID.hasPrefix(entry.key + "-")
        })?.key {
            return exactOrPrefixed
        }
        if subscriptionID.contains("astrenza-gap-notes") {
            return requestsByGroupID.first { $0.value.gap != nil }?.key
        }
        if subscriptionID.contains("astrenza-older-notes") {
            return requestsByGroupID.first { $0.value.isOlderPage }?.key
        }
        return nil
    }

    @discardableResult
    func remove(groupID: String) -> PendingBackwardRequest? {
        requestsByGroupID.removeValue(forKey: groupID)
    }

    func appendSourceRequestID(_ requestID: String, for key: String) {
        requestsByGroupID[key]?.appendSourceRequestID(requestID)
    }

    func recordTimelineEvent(_ eventID: String, for key: String) {
        guard var request = requestsByGroupID[key] else { return }
        request.recordTimelineEvent(eventID)
        requestsByGroupID[key] = request
    }

    func beginGapReconciliation(
        gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) -> String {
        let reconciliationID = Self.gapReconciliationID(gap: gap, context: context)
        activeGapReconciliationIDs.insert(reconciliationID)
        return reconciliationID
    }

    func endGapReconciliation(_ reconciliationID: String) {
        activeGapReconciliationIDs.remove(reconciliationID)
    }

    private static func gapReconciliationID(
        gap: PendingGapBackfill,
        context: HomeFeedRuntimeContext
    ) -> String {
        "\(context.feedID)#\(context.revision):\(gap.newerPostID)-\(gap.olderPostID)"
    }
}

struct PendingBackwardRequest: Equatable, Sendable {
    let feedContext: HomeFeedRuntimeContext?
    let isOlderPage: Bool
    let olderAnchorPostID: String?
    let gap: PendingGapBackfill?
    private(set) var receivedTimelineEventCount: Int
    private(set) var receivedTimelineEventIDs: [String]
    private(set) var sourceRequestIDs: [String]

    init(
        feedContext: HomeFeedRuntimeContext? = nil,
        isOlderPage: Bool = false,
        olderAnchorPostID: String? = nil,
        gap: PendingGapBackfill? = nil,
        receivedTimelineEventCount: Int = 0,
        receivedTimelineEventIDs: [String] = [],
        sourceRequestIDs: [String] = []
    ) {
        self.feedContext = feedContext
        self.isOlderPage = isOlderPage
        self.olderAnchorPostID = olderAnchorPostID
        self.gap = gap
        self.receivedTimelineEventCount = receivedTimelineEventCount
        self.receivedTimelineEventIDs = receivedTimelineEventIDs
        self.sourceRequestIDs = sourceRequestIDs
    }

    fileprivate mutating func appendSourceRequestID(_ requestID: String) {
        sourceRequestIDs.append(requestID)
    }

    fileprivate mutating func recordTimelineEvent(_ eventID: String) {
        receivedTimelineEventCount += 1
        if !receivedTimelineEventIDs.contains(eventID) {
            receivedTimelineEventIDs.append(eventID)
        }
    }
}

struct PendingGapBackfill: Equatable, Sendable {
    let newerPostID: String
    let olderPostID: String
    let direction: TimelineGapFillDirection

    var stableAnchorPostID: String {
        switch direction {
        case .newer:
            olderPostID
        case .older:
            newerPostID
        }
    }
}
