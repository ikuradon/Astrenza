struct HomeTimelineNavigationState {
    var timelinePath: [HomeTimelineNavigationRoute] = []
    var profilePath: [HomeTimelineNavigationRoute] = []

    var isPresentingDetail: Bool {
        !timelinePath.isEmpty || !profilePath.isEmpty
    }

    mutating func openPost(
        _ post: TimelinePost,
        on stack: HomeTimelineNavigationStack
    ) {
        append(
            .post(HomeTimelinePostRoute(post: post)),
            on: stack
        )
    }

    mutating func openProfile(
        from post: TimelinePost,
        on stack: HomeTimelineNavigationStack
    ) {
        append(
            .profile(HomeTimelineProfileRoute(post: post)),
            on: stack
        )
    }

    private mutating func append(
        _ route: HomeTimelineNavigationRoute,
        on stack: HomeTimelineNavigationStack
    ) {
        switch stack {
        case .timeline:
            timelinePath.append(route)
        case .profile:
            profilePath.append(route)
        }
    }
}

enum HomeTimelineNavigationStack {
    case timeline
    case profile
}

enum HomeTimelineNavigationRoute: Hashable {
    case post(HomeTimelinePostRoute)
    case profile(HomeTimelineProfileRoute)
}

struct HomeTimelinePostRoute: Identifiable, Hashable {
    let post: TimelinePost

    var id: TimelinePost.ID {
        post.id
    }

    static func == (
        lhs: HomeTimelinePostRoute,
        rhs: HomeTimelinePostRoute
    ) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct HomeTimelineProfileRoute: Identifiable, Hashable {
    let post: TimelinePost

    var id: String {
        post.author.pubkey
    }

    static func == (
        lhs: HomeTimelineProfileRoute,
        rhs: HomeTimelineProfileRoute
    ) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
