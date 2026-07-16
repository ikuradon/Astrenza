struct HomeStateContextEnvironment: Sendable {
    let projection: HomeTimelineStateInteractionEnvironment.ProjectionProvider
    let applications: HomeTimelineStoreApplicationEffects
}

@MainActor
struct HomeStateContextFactory {
    private let stateContext: HomeTimelineStateInteractionContext

    init(environment: HomeStateContextEnvironment) {
        let router = HomeTimelineStoreApplicationRouter(
            applications: environment.applications
        )
        stateContext = HomeTimelineStateInteractionContext(
            effects: HomeTimelineStateInteractionEffects(
                environment: HomeTimelineStateInteractionEnvironment(
                    projection: environment.projection
                ),
                apply: { application in
                    router.apply(application)
                }
            )
        )
    }

    func context() -> HomeTimelineStateInteractionContext {
        stateContext
    }
}
