struct HomeTimelineInteractionContext {
    let hasLiveAccount: Bool
    let timeline: TimelineKind

    var canMutateLiveHome: Bool {
        hasLiveAccount && timeline == .home
    }
}
