import AstrenzaCore
import Foundation
import Observation

struct HashtagFeedIdentity: Equatable, Hashable, Sendable {
    let hashtag: String

    init?(hashtag: String) {
        let trimmed = hashtag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "#" })
        let normalized = String(trimmed)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        self.hashtag = normalized
    }

    var title: String { "#\(hashtag)" }

    func feedID(accountID: String) -> String {
        "feed:hashtag:\(accountID):\(stableIdentifier)"
    }

    func timelineKey(accountID: String) -> String {
        "hashtag:\(accountID):\(stableIdentifier)"
    }

    func subscriptionGroupID(accountID: String) -> String {
        "astrenza-hashtag-\(Self.stableHash(accountID))-\(stableIdentifier)"
    }

    private var stableIdentifier: String {
        Self.stableHash(hashtag)
    }

    static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

struct HashtagTimelineDependencies: Sendable {
    let eventStore: NostrEventStore
    let relayRuntime: NostrRelayRuntime?
    let relayClient: any NostrRelayFetching
    let dependencyResolver: HomeTimelineDependencyResolutionCoordinator
}

private struct HashtagRelayFetchResult: Sendable {
    let relayURL: String
    let events: [NostrEvent]
    let didFail: Bool
}

@MainActor
@Observable
final class HashtagTimelineStore {
    private static let pageLimit = 100
    private static let initialWindowLimit = 240
    private static let maximumWindowLimit = 1_000

    let identity: HashtagFeedIdentity
    let accountID: String
    private(set) var entries: [TimelineFeedEntry] = []
    private(set) var contentRevision = 0
    private(set) var isLoadingInitial = true
    private(set) var isRefreshing = false
    private(set) var isLoadingOlder = false
    private(set) var isRealtime = false
    private(set) var hasMoreOlder = true
    private(set) var errorMessage: String?

    private let timelineStore: NostrHomeTimelineStore
    private let dependencies: HashtagTimelineDependencies
    private let repository: HashtagFeedRepository
    private let restoreAnchorEventID: String?
    private var materializedEvents: [NostrEvent] = []
    private var windowLimit = HashtagTimelineStore.initialWindowLimit
    private var isStarted = false
    @ObservationIgnored private var runtimeEventTask: Task<Void, Never>?
    @ObservationIgnored private var olderTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPresentationTask: Task<Void, Never>?
    @ObservationIgnored private var forwardRemovalTask: Task<Void, Never>?

    init(
        identity: HashtagFeedIdentity,
        accountID: String,
        timelineStore: NostrHomeTimelineStore,
        dependencies: HashtagTimelineDependencies,
        restoreAnchorEventID: String?
    ) {
        self.identity = identity
        self.accountID = accountID
        self.timelineStore = timelineStore
        self.dependencies = dependencies
        self.restoreAnchorEventID = restoreAnchorEventID
        repository = HashtagFeedRepository(
            identity: identity,
            accountID: accountID,
            eventStore: dependencies.eventStore
        )
    }

    var timelineKey: String {
        identity.timelineKey(accountID: accountID)
    }

    var emptyState: TimelineEmptyState {
        if isLoadingInitial {
            return TimelineEmptyState(
                title: "Loading \(identity.title)",
                message: "Loading saved notes and checking relays for newer matches.",
                systemName: "number",
                primaryActionTitle: "Loading",
                secondaryActionTitle: nil
            )
        }
        if let errorMessage {
            return TimelineEmptyState(
                title: "Tag timeline unavailable",
                message: errorMessage,
                systemName: "exclamationmark.triangle",
                primaryActionTitle: "Retry",
                secondaryActionTitle: nil
            )
        }
        return TimelineEmptyState(
            title: "No notes for \(identity.title)",
            message: "No matching notes are stored locally or available from your read relays yet.",
            systemName: "number",
            primaryActionTitle: "Update",
            secondaryActionTitle: nil
        )
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        if let forwardRemovalTask {
            await forwardRemovalTask.value
            self.forwardRemovalTask = nil
        }
        isLoadingInitial = entries.isEmpty
        errorMessage = nil
        startRuntimeEventObservation()

        do {
            let window = try await repository.prepare(
                windowLimit: windowLimit,
                restoreAnchorEventID: restoreAnchorEventID
            )
            apply(window)
            await resolveDependencies(for: materializedEvents)
            try Task.checkCancellation()
            await installForwardSubscription()
            _ = await fetchAndApply(
                direction: materializedEvents.isEmpty ? .initial : .newer
            )
        } catch is CancellationError {
            stop()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingInitial = false
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        isRealtime = false
        runtimeEventTask?.cancel()
        runtimeEventTask = nil
        olderTask?.cancel()
        olderTask = nil
        isLoadingOlder = false
        pendingPresentationTask?.cancel()
        pendingPresentationTask = nil
        guard let runtime = dependencies.relayRuntime else { return }
        let groupID = identity.subscriptionGroupID(accountID: accountID)
        forwardRemovalTask = Task {
            try? await runtime.installForward(
                [],
                replacingGroupIDsWithPrefix: groupID
            )
        }
    }

    func refresh() async -> Bool {
        guard isStarted, !isLoadingInitial, !isRefreshing else {
            return false
        }
        isRefreshing = true
        defer { isRefreshing = false }
        errorMessage = nil
        return await fetchAndApply(direction: .newer)
    }

    func loadOlder() {
        guard isStarted, !isLoadingOlder, hasMoreOlder else { return }
        isLoadingOlder = true
        olderTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isLoadingOlder = false
                olderTask = nil
            }
            windowLimit = min(
                Self.maximumWindowLimit,
                windowLimit + Self.pageLimit
            )
            if let oldestCreatedAt = materializedEvents.map(\.createdAt).min(),
               let localWindow = try? await repository.projectLocalOlder(
                   until: max(0, oldestCreatedAt - 1),
                   windowLimit: windowLimit,
                   restoreAnchorEventID: restoreAnchorEventID
               ) {
                guard !Task.isCancelled, isStarted else { return }
                apply(localWindow)
                await resolveDependencies(for: localWindow.events)
            }
            _ = await fetchAndApply(direction: .older)
        }
    }

    func refreshPresentationForDependencyChange() {
        let nextEntries = timelineStore.publicFeedEntries(
            events: materializedEvents
        )
        applyEntries(nextEntries)
    }

    private enum FetchDirection {
        case initial
        case newer
        case older
    }

    private func fetchAndApply(direction: FetchDirection) async -> Bool {
        let previousIDs = Set(materializedEvents.map(\.id))
        let results = await fetch(direction: direction)
        guard !Task.isCancelled else { return false }
        let successfulResults = results.filter { !$0.didFail }
        let fetched = successfulResults.flatMap { result in
            result.events.map {
                HashtagRelayEvent(relayURL: result.relayURL, event: $0)
            }
        }
        if direction == .older {
            hasMoreOlder = successfulResults.contains {
                $0.events.count >= Self.pageLimit
            }
        }
        guard !fetched.isEmpty else {
            if results.allSatisfy(\.didFail), entries.isEmpty {
                errorMessage = "The configured read relays did not return a response."
            }
            return false
        }

        do {
            let window = try await repository.ingest(
                fetched,
                reason: reason(for: direction),
                windowLimit: windowLimit,
                restoreAnchorEventID: restoreAnchorEventID
            )
            apply(window)
            await resolveDependencies(for: fetched.map(\.event))
            return !Set(materializedEvents.map(\.id)).subtracting(previousIDs).isEmpty
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func fetch(
        direction: FetchDirection
    ) async -> [HashtagRelayFetchResult] {
        let relays = relayURLs
        guard !relays.isEmpty else { return [] }
        let request = NostrRelayRequest(
            subscriptionID: "\(identity.subscriptionGroupID(accountID: accountID))-\(reason(for: direction))",
            filters: [filter(for: direction)]
        )
        let relayClient = dependencies.relayClient
        return await withTaskGroup(
            of: HashtagRelayFetchResult.self,
            returning: [HashtagRelayFetchResult].self
        ) { group in
            for relayURL in relays {
                group.addTask {
                    do {
                        return HashtagRelayFetchResult(
                            relayURL: relayURL,
                            events: try await relayClient.fetch(
                                relayURL: relayURL,
                                request: request
                            ),
                            didFail: false
                        )
                    } catch {
                        return HashtagRelayFetchResult(
                            relayURL: relayURL,
                            events: [],
                            didFail: true
                        )
                    }
                }
            }
            var output: [HashtagRelayFetchResult] = []
            for await result in group {
                output.append(result)
            }
            return output
        }
    }

    private func filter(
        for direction: FetchDirection
    ) -> [String: AnySendableJSON] {
        var filter: [String: AnySendableJSON] = [
            "kinds": .ints([1, 6]),
            "#t": .strings([identity.hashtag]),
            "limit": .int(Self.pageLimit)
        ]
        switch direction {
        case .initial:
            break
        case .newer:
            if let newest = materializedEvents.map(\.createdAt).max() {
                filter["since"] = .int(max(0, newest - 10))
            }
        case .older:
            if let oldest = materializedEvents.map(\.createdAt).min() {
                filter["until"] = .int(max(0, oldest - 1))
            }
        }
        return filter
    }

    private func reason(for direction: FetchDirection) -> String {
        switch direction {
        case .initial: "initial"
        case .newer: "newer"
        case .older: "older"
        }
    }

    private var relayURLs: [String] {
        var seen = Set<String>()
        return (
            timelineStore.resolvedRelays +
                (timelineStore.account?.discoveryRelays ?? []) +
                NostrHomeTimelineLoader.defaultBootstrapRelays
        ).filter { seen.insert($0).inserted }
    }

    private func installForwardSubscription() async {
        guard let runtime = dependencies.relayRuntime else { return }
        let groupID = identity.subscriptionGroupID(accountID: accountID)
        var filter: [String: AnySendableJSON] = [
            "kinds": .ints([1, 6]),
            "#t": .strings([identity.hashtag])
        ]
        if let newest = materializedEvents.map(\.createdAt).max() {
            filter["since"] = .int(max(0, newest - 10))
        }
        do {
            try await runtime.installForward(NostrREQPacket(
                strategy: .forward,
                subscriptionID: "\(groupID)-forward",
                groupID: groupID,
                filters: [filter],
                relayURLs: relayURLs
            ))
            isRealtime = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startRuntimeEventObservation() {
        guard runtimeEventTask == nil,
              let runtime = dependencies.relayRuntime
        else { return }
        let subscriptionID = "\(identity.subscriptionGroupID(accountID: accountID))-forward"
        runtimeEventTask = Task { [weak self] in
            let stream = await runtime.events()
            for await packet in stream {
                guard !Task.isCancelled else { return }
                switch packet {
                case .event(let relayURL, let receivedSubscriptionID, let event)
                    where receivedSubscriptionID == subscriptionID:
                    await self?.ingestForwardEvent(
                        event,
                        relayURL: relayURL
                    )
                case .closed(_, let receivedSubscriptionID, let message)
                    where receivedSubscriptionID == subscriptionID:
                    self?.errorMessage = message
                default:
                    break
                }
            }
        }
    }

    private func ingestForwardEvent(
        _ event: NostrEvent,
        relayURL: String
    ) async {
        do {
            _ = try await repository.ingest(
                [HashtagRelayEvent(relayURL: relayURL, event: event)],
                reason: "forward",
                windowLimit: windowLimit,
                restoreAnchorEventID: restoreAnchorEventID
            )
            await resolveDependencies(for: [event])
            schedulePresentationReload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func schedulePresentationReload() {
        pendingPresentationTask?.cancel()
        pendingPresentationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled,
                  let self,
                  let window = try? await repository.loadWindow(
                      limit: windowLimit,
                      restoreAnchorEventID: restoreAnchorEventID
                  )
            else { return }
            apply(window)
        }
    }

    private func apply(_ window: NostrFeedWindow?) {
        guard let window else { return }
        materializedEvents = window.events
        applyEntries(timelineStore.publicFeedEntries(events: window.events))
    }

    private func resolveDependencies(for events: [NostrEvent]) async {
        guard !events.isEmpty else { return }
        let result = await dependencies.dependencyResolver.enqueueDependencies(
            for: events,
            liveMetadataEvents: [],
            liveNoteEventIDs: Set(materializedEvents.map(\.id)),
            availableRelayURLs: relayURLs
        )
        if result.didEnqueueSourceDependencies {
            _ = dependencies.dependencyResolver.scheduleSourcePacketInstall(
                onFailure: { _ in }
            )
        }
    }

    private func applyEntries(_ nextEntries: [TimelineFeedEntry]) {
        guard TimelineRenderFingerprint.entries(nextEntries) !=
            TimelineRenderFingerprint.entries(entries)
        else { return }
        entries = nextEntries
        contentRevision &+= 1
    }
}
