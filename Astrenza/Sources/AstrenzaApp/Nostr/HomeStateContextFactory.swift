struct HomeStateContextEnvironment: Sendable {
    let projection: HomeTimelineStateInteractionEnvironment.ProjectionProvider
    let apply: HomeTimelineStateInteractionEffects.ApplicationEffect
}

@MainActor
struct HomeStateContextFactory {
    private let stateContext: HomeTimelineStateInteractionContext

    init(environment: HomeStateContextEnvironment) {
        stateContext = HomeTimelineStateInteractionContext(
            effects: HomeTimelineStateInteractionEffects(
                environment: HomeTimelineStateInteractionEnvironment(
                    projection: environment.projection
                ),
                apply: environment.apply
            )
        )
    }

    func context() -> HomeTimelineStateInteractionContext {
        stateContext
    }
}
