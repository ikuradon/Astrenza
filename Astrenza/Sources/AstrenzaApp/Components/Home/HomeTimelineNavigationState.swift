struct HomeTimelineNavigationState {
    var timelinePath: [HomeTimelineNavigationRoute] = []
    var profilePath: [HomeTimelineNavigationRoute] = []

    var isPresentingDetail: Bool {
        !timelinePath.isEmpty || !profilePath.isEmpty
    }

    var activePost: TimelinePost? {
        let route = profilePath.last ?? timelinePath.last
        switch route {
        case .post(let route): return route.post
        case .profile(let route): return route.post
        case .hashtag: return nil
        case nil: return nil
        }
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

    mutating func openHashtag(
        _ hashtag: String,
        on stack: HomeTimelineNavigationStack
    ) {
        guard let route = HomeTimelineHashtagRoute(hashtag: hashtag) else {
            return
        }
        append(.hashtag(route), on: stack)
    }

    private mutating func append(
        _ route: HomeTimelineNavigationRoute,
        on stack: HomeTimelineNavigationStack
    ) {
        switch stack {
        case .timeline:
            guard timelinePath.last != route else { return }
            timelinePath.append(route)
        case .profile:
            guard profilePath.last != route else { return }
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
    case hashtag(HomeTimelineHashtagRoute)
}

struct HomeTimelineHashtagRoute: Identifiable, Hashable {
    let hashtag: String

    init?(hashtag: String) {
        guard let identity = HashtagFeedIdentity(hashtag: hashtag) else {
            return nil
        }
        self.hashtag = identity.hashtag
    }

    var id: String { hashtag }
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
