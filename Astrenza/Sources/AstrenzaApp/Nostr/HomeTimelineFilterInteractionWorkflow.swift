import AstrenzaCore
import Foundation

@MainActor
protocol HomeTimelineFilterManaging: AnyObject {
    func effectiveRuleSet(
        accountID: String?,
        now: Int
    ) -> NostrFilterRuleSet?

    @discardableResult
    func suspend() -> Bool

    @discardableResult
    func resume() -> Bool
}

extension HomeTimelineFilterCoordinator: HomeTimelineFilterManaging {}

enum HomeTimelineFilterIntent: Equatable, Sendable {
    case suspend
    case resume
}

enum HomeTimelineFilterStoreAction: Equatable, Sendable {
    case invalidateListEntries
    case materializeEntries
}

struct HomeFilterInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineFilterStoreAction
    ) -> Void

    let apply: ApplicationEffect
}

struct HomeFilterInteractionContext: Sendable {
    let effects: HomeFilterInteractionEffects
}

@MainActor
final class HomeTimelineFilterInteractionWorkflow {
    typealias TimestampProvider = @MainActor @Sendable () -> Int

    private let filter: any HomeTimelineFilterManaging
    private let currentTimestamp: TimestampProvider

    init(
        filter: any HomeTimelineFilterManaging,
        currentTimestamp: @escaping TimestampProvider = {
            Int(Date().timeIntervalSince1970)
        }
    ) {
        self.filter = filter
        self.currentTimestamp = currentTimestamp
    }

    func effectiveRuleSet(accountID: String?) -> NostrFilterRuleSet? {
        filter.effectiveRuleSet(
            accountID: accountID,
            now: currentTimestamp()
        )
    }

    @discardableResult
    func perform(
        _ intent: HomeTimelineFilterIntent,
        context: HomeFilterInteractionContext
    ) -> Bool {
        let didChange = switch intent {
        case .suspend:
            filter.suspend()
        case .resume:
            filter.resume()
        }
        guard didChange else { return false }

        context.effects.apply(.invalidateListEntries)
        context.effects.apply(.materializeEntries)
        return true
    }
}
