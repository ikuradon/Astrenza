import AstrenzaCore
import Foundation

struct RuntimeSubscriptionKey: Hashable, Sendable {
    let relayURL: String
    let subscriptionID: String
}

enum HomeTimelineInitialSyncState: Equatable, Sendable {
    case awaitingRelayResponses
    case synchronized
    case degraded
    case unavailable

    var isSettled: Bool {
        self != .awaitingRelayResponses
    }
}

struct HomeTimelineInitialSyncProgress: Equatable, Sendable {
    let expectedRelayCount: Int
    let completedRelayCount: Int
    let successfulRelayCount: Int
    let failedRelayCount: Int

    var state: HomeTimelineInitialSyncState {
        guard expectedRelayCount > 0,
              completedRelayCount == expectedRelayCount
        else {
            return .awaitingRelayResponses
        }
        if successfulRelayCount == expectedRelayCount {
            return .synchronized
        }
        return successfulRelayCount > 0 ? .degraded : .unavailable
    }
}

struct HomeFeedRuntimeContext: Equatable, Sendable {
    let feedID: String
    let accountID: String
    let revision: Int
    let specificationHash: String
    let allowedAuthors: Set<String>

    init(definition: NostrFeedDefinitionRecord) {
        feedID = definition.feedID
        accountID = definition.accountID
        revision = definition.revision
        specificationHash = definition.specificationHash
        let specification = try? JSONDecoder().decode(
            HomeFeedSpecification.self,
            from: definition.specificationJSON
        )
        allowedAuthors = Set(specification?.authors ?? [])
    }

    func matches(_ definition: NostrFeedDefinitionRecord?) -> Bool {
        guard let definition else { return false }
        return feedID == definition.feedID &&
            accountID == definition.accountID &&
            revision == definition.revision &&
            specificationHash == definition.specificationHash
    }

    func includes(_ event: NostrEvent) -> Bool {
        allowedAuthors.isEmpty || allowedAuthors.contains(event.pubkey)
    }
}

struct RuntimeSyncWindow: Equatable {
    private(set) var newestCreatedAt: Int?
    private(set) var oldestCreatedAt: Int?
    private(set) var eventCount = 0
    private(set) var newestCursor: NostrTimelineEntryCursor?
    private(set) var oldestCursor: NostrTimelineEntryCursor?

    mutating func include(_ event: NostrEvent) {
        newestCreatedAt = [newestCreatedAt, event.createdAt].compactMap { $0 }.max()
        oldestCreatedAt = [oldestCreatedAt, event.createdAt].compactMap { $0 }.min()
        eventCount += 1
        let cursor = NostrTimelineEntryCursor(sortTimestamp: event.createdAt, eventID: event.id)
        if let current = newestCursor {
            if cursor.sortTimestamp > current.sortTimestamp ||
                (cursor.sortTimestamp == current.sortTimestamp && cursor.eventID < current.eventID) {
                newestCursor = cursor
            }
        } else {
            newestCursor = cursor
        }
        if let current = oldestCursor {
            if cursor.sortTimestamp < current.sortTimestamp ||
                (cursor.sortTimestamp == current.sortTimestamp && cursor.eventID > current.eventID) {
                oldestCursor = cursor
            }
        } else {
            oldestCursor = cursor
        }
    }
}

struct HomeTimelineRuntimeSyncState {
    private enum InitialForwardResult: Equatable {
        case eose
        case failed
    }

    struct ActiveRequest: Equatable {
        let key: RuntimeSubscriptionKey
        let requestID: String
        let context: HomeFeedRuntimeContext?
        let window: RuntimeSyncWindow
    }

    private var windowsBySubscription: [RuntimeSubscriptionKey: RuntimeSyncWindow] = [:]
    private var requestIDsBySubscription: [RuntimeSubscriptionKey: String] = [:]
    private var contextsBySubscription: [RuntimeSubscriptionKey: HomeFeedRuntimeContext] = [:]
    private var forwardContextsByGroupID: [String: HomeFeedRuntimeContext] = [:]
    private var expectedForwardSubscriptions = Set<RuntimeSubscriptionKey>()
    private var forwardEOSESubscriptions = Set<RuntimeSubscriptionKey>()
    private var initialForwardSubscriptions = Set<RuntimeSubscriptionKey>()
    private var initialForwardResults: [RuntimeSubscriptionKey: InitialForwardResult] = [:]

    // Forward REQは購読ごとにEOSE後のlive streamへ移る。1 relayの応答待ちで
    // 他relayのlive表示と追従を止めず、cohort全体の完了はinitialSyncProgressで扱う。
    var isRealtime: Bool {
        !forwardEOSESubscriptions.isEmpty
    }

    func isRealtime(for key: RuntimeSubscriptionKey) -> Bool {
        forwardEOSESubscriptions.contains(key)
    }

    var initialSyncState: HomeTimelineInitialSyncState {
        initialSyncProgress.state
    }

    var initialSyncProgress: HomeTimelineInitialSyncProgress {
        let successfulRelayCount = initialForwardSubscriptions.reduce(into: 0) {
            count, key in
            if initialForwardResults[key] == .eose {
                count += 1
            }
        }
        let failedRelayCount = initialForwardSubscriptions.reduce(into: 0) {
            count, key in
            if initialForwardResults[key] == .failed {
                count += 1
            }
        }
        return HomeTimelineInitialSyncProgress(
            expectedRelayCount: initialForwardSubscriptions.count,
            completedRelayCount: successfulRelayCount + failedRelayCount,
            successfulRelayCount: successfulRelayCount,
            failedRelayCount: failedRelayCount
        )
    }

    var activeRequestCount: Int {
        requestIDsBySubscription.count
    }

    var activeContextCount: Int {
        contextsBySubscription.count
    }

    mutating func reset() {
        windowsBySubscription.removeAll()
        requestIDsBySubscription.removeAll()
        contextsBySubscription.removeAll()
        forwardContextsByGroupID.removeAll()
        expectedForwardSubscriptions.removeAll()
        forwardEOSESubscriptions.removeAll()
        initialForwardSubscriptions.removeAll()
        initialForwardResults.removeAll()
    }

    mutating func prepareForwardSubscriptions(_ subscriptions: Set<RuntimeSubscriptionKey>) {
        let initialSyncWasSettled = initialSyncState.isSettled
        if !initialSyncWasSettled {
            // 初回表示のcohortだけを更新する。settle後にrelay planが増減しても、
            // current realtime状態の変化で起動時の完了表示を巻き戻さない。
            initialForwardSubscriptions = subscriptions
            initialForwardResults = initialForwardResults.filter {
                subscriptions.contains($0.key)
            }
        }
        expectedForwardSubscriptions = subscriptions
        forwardEOSESubscriptions.removeAll()
    }

    mutating func beginForwardAttempt(_ key: RuntimeSubscriptionKey) {
        forwardEOSESubscriptions.remove(key)
    }

    mutating func invalidateForwardSubscription(_ key: RuntimeSubscriptionKey) {
        forwardEOSESubscriptions.remove(key)
    }

    mutating func invalidateForwardSubscriptions(relayURL: String) {
        forwardEOSESubscriptions = forwardEOSESubscriptions.filter { $0.relayURL != relayURL }
    }

    mutating func markForwardEOSE(_ key: RuntimeSubscriptionKey) {
        guard expectedForwardSubscriptions.contains(key) else { return }
        forwardEOSESubscriptions.insert(key)
        if initialForwardSubscriptions.contains(key) {
            initialForwardResults[key] = .eose
        }
    }

    mutating func markForwardFailure(_ key: RuntimeSubscriptionKey) {
        guard expectedForwardSubscriptions.contains(key),
              initialForwardSubscriptions.contains(key),
              initialForwardResults[key] != .eose
        else { return }
        initialForwardResults[key] = .failed
    }

    mutating func registerForwardContext(_ context: HomeFeedRuntimeContext, groupID: String) {
        forwardContextsByGroupID[groupID] = context
    }

    func forwardContext(groupID: String) -> HomeFeedRuntimeContext? {
        forwardContextsByGroupID[groupID]
    }

    func requestID(for key: RuntimeSubscriptionKey) -> String? {
        requestIDsBySubscription[key]
    }

    func context(for key: RuntimeSubscriptionKey) -> HomeFeedRuntimeContext? {
        contextsBySubscription[key]
    }

    mutating func activateRequest(
        key: RuntimeSubscriptionKey,
        requestID: String,
        context: HomeFeedRuntimeContext
    ) {
        requestIDsBySubscription[key] = requestID
        contextsBySubscription[key] = context
        windowsBySubscription[key] = RuntimeSyncWindow()
    }

    mutating func takeRequest(for key: RuntimeSubscriptionKey) -> ActiveRequest? {
        let window = windowsBySubscription.removeValue(forKey: key) ?? RuntimeSyncWindow()
        let context = contextsBySubscription.removeValue(forKey: key)
        guard let requestID = requestIDsBySubscription.removeValue(forKey: key) else {
            return nil
        }
        return ActiveRequest(key: key, requestID: requestID, context: context, window: window)
    }

    mutating func takeRequest(
        for key: RuntimeSubscriptionKey,
        matching requestID: String
    ) -> ActiveRequest? {
        guard requestIDsBySubscription[key] == requestID else { return nil }
        return takeRequest(for: key)
    }

    func activeRequests() -> [ActiveRequest] {
        requestIDsBySubscription.map { key, requestID in
            ActiveRequest(
                key: key,
                requestID: requestID,
                context: contextsBySubscription[key],
                window: windowsBySubscription[key] ?? RuntimeSyncWindow()
            )
        }
    }

    mutating func record(_ event: NostrEvent, for key: RuntimeSubscriptionKey) {
        windowsBySubscription[key, default: RuntimeSyncWindow()].include(event)
    }

    mutating func finishWindow(for key: RuntimeSubscriptionKey) -> RuntimeSyncWindow {
        windowsBySubscription.removeValue(forKey: key) ?? RuntimeSyncWindow()
    }
}
