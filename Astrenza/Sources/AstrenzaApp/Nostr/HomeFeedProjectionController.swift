import AstrenzaCore
import Foundation

@MainActor
final class HomeFeedProjectionController {
    let windowLimit: Int
    let retainedWindowLimit: Int
    let anchorLeadingLimit: Int
    let anchorTrailingLimit: Int

    private struct DefinitionIdentity: Equatable {
        let accountID: String
        let sourceAuthors: [String]
    }

    private let definitionPreparer: any HomeFeedDefinitionPreparing
    private let windowLoader: any HomeFeedWindowLoading
    private var definitionTask: Task<
        HomeFeedDefinitionPreparationOutcome,
        Never
    >?
    private var pendingDefinitionIdentity: DefinitionIdentity?
    private var pendingDefinitionGeneration: UInt64?
    private(set) var definition: NostrFeedDefinitionRecord?
    private(set) var window: NostrFeedWindow?
    private(set) var generation: UInt64 = 0
    private(set) var sourceAuthors: [String]?

    init(
        eventStore: NostrEventStore?,
        windowLimit: Int = 240,
        retainedWindowLimit: Int = HomeTimelinePersistenceProjection.retainedEventLimit,
        anchorLeadingLimit: Int = 80,
        anchorTrailingLimit: Int = 160,
        definitionPreparer: (any HomeFeedDefinitionPreparing)? = nil,
        windowLoader: (any HomeFeedWindowLoading)? = nil
    ) {
        self.definitionPreparer = definitionPreparer ?? HomeFeedDefinitionPreparer(
            eventStore: eventStore
        )
        self.windowLoader = windowLoader ?? HomeFeedWindowLoader(
            eventStore: eventStore
        )
        self.windowLimit = windowLimit
        self.retainedWindowLimit = retainedWindowLimit
        self.anchorLeadingLimit = anchorLeadingLimit
        self.anchorTrailingLimit = anchorTrailingLimit
    }
}

extension HomeFeedProjectionController {
    func reset() {
        cancelDefinitionPreparation()
        definition = nil
        window = nil
        sourceAuthors = nil
        generation &+= 1
    }

    func clearWindow() {
        cancelDefinitionPreparation()
        window = nil
        generation &+= 1
    }

    func definitionPlan(
        accountID: String,
        followedPubkeys: [String],
        now: Int
    ) async -> HomeFeedDefinitionPlan? {
        await definitionPreparer.plan(HomeFeedDefinitionPlanRequest(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            now: now
        ))
    }

    func prewarmDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        now: Int = Int(Date().timeIntervalSince1970)
    ) {
        let identity = definitionIdentity(
            accountID: accountID,
            followedPubkeys: followedPubkeys
        )
        guard !hasPreparedDefinition(identity),
              pendingDefinitionIdentity != identity
        else { return }
        _ = startDefinitionPreparation(
            identity: identity,
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents,
            now: now
        )
    }

    func feedID(accountID: String) -> String? {
        if definition?.accountID == accountID {
            return definition?.feedID
        }
        guard pendingDefinitionIdentity?.accountID == accountID else {
            return nil
        }
        return HomeFeedProjectionBuilder.feedID(accountID: accountID)
    }

    @discardableResult
    func ensureDefinition(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        now: Int = Int(Date().timeIntervalSince1970)
    ) async -> Bool {
        let identity = definitionIdentity(
            accountID: accountID,
            followedPubkeys: followedPubkeys
        )
        if hasPreparedDefinition(identity) {
            return true
        }

        if pendingDefinitionIdentity == identity,
           let definitionTask,
           let pendingDefinitionGeneration {
            let outcome = await definitionTask.value
            return applyDefinitionPreparation(
                outcome,
                identity: identity,
                generation: pendingDefinitionGeneration
            )
        }

        let preparation = startDefinitionPreparation(
            identity: identity,
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents,
            now: now
        )
        let outcome = await preparation.task.value
        return applyDefinitionPreparation(
            outcome,
            identity: identity,
            generation: preparation.generation
        )
    }

    @discardableResult
    func reloadNewest(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    ) async -> NostrFeedWindow? {
        guard await ensureDefinition(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents
        ) else { return nil }
        guard let definition else { return nil }
        let loadGeneration = beginWindowLoad()
        guard let loaded = try? await windowLoader.load(
            HomeFeedWindowLoadRequest(
                definition: definition,
                selection: .newest(limit: windowLimit),
                currentWindow: nil
            )
        ), canApplyWindow(
            generation: loadGeneration,
            definition: definition
        ) else { return nil }
        window = loaded
        return loaded
    }

    @discardableResult
    func reload(
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool
    ) async -> NostrFeedWindow? {
        guard await ensureDefinition(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents
        ) else { return nil }
        guard let definition else { return nil }
        let selection: HomeFeedWindowSelection
        let currentWindow: NostrFeedWindow?
        if let anchorEventID {
            selection = .anchored(
                eventID: anchorEventID,
                leadingLimit: anchorLeadingLimit,
                trailingLimit: anchorTrailingLimit,
                retainedLimit: retainedWindowLimit
            )
            currentWindow = mergingWithCurrentWindow ? window : nil
        } else {
            selection = .newest(limit: windowLimit)
            currentWindow = nil
        }
        let loadGeneration = beginWindowLoad()
        guard let loaded = try? await windowLoader.load(
            HomeFeedWindowLoadRequest(
                definition: definition,
                selection: selection,
                currentWindow: currentWindow
            )
        ), canApplyWindow(
            generation: loadGeneration,
            definition: definition
        ) else { return nil }
        window = loaded
        return loaded
    }

    func activate(
        definition: NostrFeedDefinitionRecord,
        window: NostrFeedWindow?,
        sourceAuthors: [String]
    ) {
        cancelDefinitionPreparation()
        self.definition = definition
        self.window = window
        self.sourceAuthors = sourceAuthors
        generation &+= 1
    }

    func activateStoredProjection(
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    ) async {
        cancelDefinitionPreparation()
        let activationGeneration = beginWindowLoad()
        guard let storedWindow = try? await windowLoader.load(
            HomeFeedWindowLoadRequest(
                definition: definition,
                selection: .newest(limit: windowLimit),
                currentWindow: nil
            )
        ) else { return }
        guard !Task.isCancelled,
              generation == activationGeneration
        else { return }
        self.definition = definition
        self.window = storedWindow
        self.sourceAuthors = sourceAuthors
    }

    func runtimeContext() -> HomeFeedRuntimeContext? {
        definition.map(HomeFeedRuntimeContext.init)
    }

    func isCurrent(_ context: HomeFeedRuntimeContext?, accountID: String?) -> Bool {
        guard let context else { return false }
        return context.matches(definition) && accountID == context.accountID
    }

    private func beginWindowLoad() -> UInt64 {
        generation &+= 1
        return generation
    }

    private func beginDefinitionPreparation() -> UInt64 {
        generation &+= 1
        return generation
    }

    private func definitionIdentity(
        accountID: String,
        followedPubkeys: [String]
    ) -> DefinitionIdentity {
        DefinitionIdentity(
            accountID: accountID,
            sourceAuthors: followedPubkeys.isEmpty ? [accountID] : followedPubkeys
        )
    }

    private func hasPreparedDefinition(_ identity: DefinitionIdentity) -> Bool {
        definition?.accountID == identity.accountID &&
            sourceAuthors == identity.sourceAuthors &&
            definitionTask == nil
    }

    private func startDefinitionPreparation(
        identity: DefinitionIdentity,
        accountID: String,
        followedPubkeys: [String],
        liveEvents: [NostrEvent],
        now: Int
    ) -> (
        task: Task<HomeFeedDefinitionPreparationOutcome, Never>,
        generation: UInt64
    ) {
        cancelDefinitionPreparation()
        let preparationGeneration = beginDefinitionPreparation()
        let definitionPreparer = definitionPreparer
        let request = HomeFeedDefinitionPreparationRequest(
            sequence: preparationGeneration,
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            liveEvents: liveEvents,
            now: now,
            windowLimit: windowLimit
        )
        let task = Task {
            await definitionPreparer.prepare(request)
        }
        definitionTask = task
        pendingDefinitionIdentity = identity
        pendingDefinitionGeneration = preparationGeneration
        return (task, preparationGeneration)
    }

    private func applyDefinitionPreparation(
        _ outcome: HomeFeedDefinitionPreparationOutcome,
        identity: DefinitionIdentity,
        generation preparationGeneration: UInt64
    ) -> Bool {
        guard generation == preparationGeneration,
              pendingDefinitionIdentity == identity,
              pendingDefinitionGeneration == preparationGeneration
        else {
            return definition?.accountID == identity.accountID &&
                sourceAuthors == identity.sourceAuthors
        }
        definitionTask = nil
        pendingDefinitionIdentity = nil
        pendingDefinitionGeneration = nil

        switch outcome {
        case .prepared(let preparation):
            definition = preparation.plan.definition
            sourceAuthors = preparation.plan.sourceAuthors
            if case .replace(let nextWindow) = preparation.windowUpdate {
                window = nextWindow
            }
            return true
        case .failed:
            definition = nil
            window = nil
            sourceAuthors = nil
            return false
        case .superseded, .unavailable:
            return false
        }
    }

    private func cancelDefinitionPreparation() {
        definitionTask?.cancel()
        definitionTask = nil
        pendingDefinitionIdentity = nil
        pendingDefinitionGeneration = nil
    }

    private func canApplyWindow(
        generation loadGeneration: UInt64,
        definition loadedDefinition: NostrFeedDefinitionRecord
    ) -> Bool {
        !Task.isCancelled &&
            generation == loadGeneration &&
            definition == loadedDefinition
    }
}
