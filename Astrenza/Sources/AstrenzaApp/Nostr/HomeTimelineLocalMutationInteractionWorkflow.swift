import AstrenzaCore
import Foundation

@MainActor
protocol HomeTimelineLocalMutationHandling: Sendable {
    @discardableResult
    func muteAuthor(
        accountID: String,
        authorPubkey: String,
        at timestamp: Int
    ) throws -> NostrFilterRuleRecord

    @discardableResult
    func bookmarkPost(
        accountID: String,
        eventID: String,
        at timestamp: Int
    ) throws -> NostrLocalBookmarkRecord
}

extension HomeTimelineLocalMutationCoordinator:
    HomeTimelineLocalMutationHandling {}

struct HomeLocalMutationInteractionState: Equatable, Sendable {
    let accountID: String?
}

enum HomeTimelineLocalMutationIntent: Equatable, Sendable {
    case muteAuthor(authorPubkey: String)
    case bookmark(eventID: String)

    fileprivate var failureTitle: String {
        switch self {
        case .muteAuthor:
            "Mute"
        case .bookmark:
            "Bookmark"
        }
    }
}

enum HomeTimelineLocalMutationStoreAction: Equatable, Sendable {
    case invalidateListEntries
    case materializeEntries
    case setPhase(NostrHomeTimelinePhase)
}

struct HomeLocalMutationInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineLocalMutationStoreAction
    ) -> Void

    let apply: ApplicationEffect
}

struct HomeLocalMutationInteractionContext: Sendable {
    let state: HomeLocalMutationInteractionState
    let effects: HomeLocalMutationInteractionEffects
}

@MainActor
final class HomeLocalMutationInteractionWorkflow {
    typealias TimestampProvider = @MainActor @Sendable () -> Int

    private let localMutation: any HomeTimelineLocalMutationHandling
    private let currentTimestamp: TimestampProvider

    init(
        localMutation: any HomeTimelineLocalMutationHandling,
        currentTimestamp: @escaping TimestampProvider = {
            Int(Date().timeIntervalSince1970)
        }
    ) {
        self.localMutation = localMutation
        self.currentTimestamp = currentTimestamp
    }

    func perform(
        _ intent: HomeTimelineLocalMutationIntent,
        context: HomeLocalMutationInteractionContext
    ) {
        guard let accountID = context.state.accountID else { return }

        do {
            try persist(
                intent,
                accountID: accountID,
                timestamp: currentTimestamp()
            )
            applySuccessActions(for: intent, effects: context.effects)
        } catch {
            context.effects.apply(.setPhase(.failed(
                "\(intent.failureTitle) failed: \(error.localizedDescription)"
            )))
        }
    }

    private func persist(
        _ intent: HomeTimelineLocalMutationIntent,
        accountID: String,
        timestamp: Int
    ) throws {
        switch intent {
        case .muteAuthor(let authorPubkey):
            try localMutation.muteAuthor(
                accountID: accountID,
                authorPubkey: authorPubkey,
                at: timestamp
            )
        case .bookmark(let eventID):
            try localMutation.bookmarkPost(
                accountID: accountID,
                eventID: eventID,
                at: timestamp
            )
        }
    }

    private func applySuccessActions(
        for intent: HomeTimelineLocalMutationIntent,
        effects: HomeLocalMutationInteractionEffects
    ) {
        guard case .muteAuthor = intent else { return }
        effects.apply(.invalidateListEntries)
        effects.apply(.materializeEntries)
    }
}
