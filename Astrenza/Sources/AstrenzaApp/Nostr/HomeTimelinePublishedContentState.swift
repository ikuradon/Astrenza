struct HomeTimelinePublishedContentState {
    private(set) var resolvedRelays: [String]
    private(set) var followedPubkeys: [String]
    private(set) var hasMoreOlder: Bool

    init(
        resolvedRelays: [String] = [],
        followedPubkeys: [String] = [],
        hasMoreOlder: Bool = true
    ) {
        self.resolvedRelays = resolvedRelays
        self.followedPubkeys = followedPubkeys
        self.hasMoreOlder = hasMoreOlder
    }

    func applying(
        _ snapshot: HomeTimelineContentSnapshot
    ) -> HomeTimelinePublishedContentState? {
        var next = self
        var didMutate = false

        if next.resolvedRelays != snapshot.resolvedRelays {
            next.resolvedRelays = snapshot.resolvedRelays
            didMutate = true
        }
        if next.followedPubkeys != snapshot.followedPubkeys {
            next.followedPubkeys = snapshot.followedPubkeys
            didMutate = true
        }
        if next.hasMoreOlder != snapshot.hasMoreOlder {
            next.hasMoreOlder = snapshot.hasMoreOlder
            didMutate = true
        }
        return didMutate ? next : nil
    }
}
