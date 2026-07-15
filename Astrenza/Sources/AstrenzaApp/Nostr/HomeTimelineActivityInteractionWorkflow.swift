@MainActor
protocol HomeTimelineActivityManaging: AnyObject {
    var snapshot: HomeTimelineActivitySnapshot { get }
    var canBeginLoadingOlder: Bool { get }

    func setPhase(
        _ phase: NostrHomeTimelinePhase
    ) -> HomeTimelineActivityTransition

    func setRealtime(
        _ isRealtime: Bool
    ) -> HomeTimelineActivityTransition

    func activityStatus(
        context: HomeTimelineActivityContext
    ) -> NostrTimelineActivityStatus?
}

extension HomeTimelineActivityCoordinator: HomeTimelineActivityManaging {}

struct HomeTimelineActivityInteractionState: Equatable, Sendable {
    let phase: NostrHomeTimelinePhase
    let isRealtime: Bool
    let canBeginLoadingOlder: Bool
}

enum HomeTimelineActivityIntent: Equatable, Sendable {
    case setPhase(NostrHomeTimelinePhase)
    case setRealtime(Bool)
}

@MainActor
final class HomeTimelineActivityInteractionWorkflow {
    private let activity: any HomeTimelineActivityManaging

    init(activity: any HomeTimelineActivityManaging) {
        self.activity = activity
    }

    var state: HomeTimelineActivityInteractionState {
        let snapshot = activity.snapshot
        return HomeTimelineActivityInteractionState(
            phase: snapshot.phase,
            isRealtime: snapshot.isRealtime,
            canBeginLoadingOlder: activity.canBeginLoadingOlder
        )
    }

    func perform(
        _ intent: HomeTimelineActivityIntent
    ) -> HomeTimelineActivityTransition {
        switch intent {
        case .setPhase(let phase):
            activity.setPhase(phase)
        case .setRealtime(let isRealtime):
            activity.setRealtime(isRealtime)
        }
    }

    func status(
        context: HomeTimelineActivityContext
    ) -> NostrTimelineActivityStatus? {
        activity.activityStatus(context: context)
    }
}
