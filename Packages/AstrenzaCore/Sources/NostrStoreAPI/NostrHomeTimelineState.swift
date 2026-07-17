import NostrProtocol

public struct NostrHomeTimelineState: Equatable, Sendable {
    public let relays: [String]
    public let followedPubkeys: [String]
    public let noteEvents: [NostrEvent]
    public let metadataEvents: [NostrEvent]
    public let relayListEvent: NostrEvent?
    public let contactListEvent: NostrEvent?
    public let authorRelayListEvents: [NostrEvent]
    public let nip05Resolutions: [String: NostrNIP05Resolution]
    public let hasMoreOlder: Bool
    public let relaySyncEvents: [NostrRelaySyncEventRecord]

    public init(
        relays: [String],
        followedPubkeys: [String],
        noteEvents: [NostrEvent],
        metadataEvents: [NostrEvent],
        relayListEvent: NostrEvent? = nil,
        contactListEvent: NostrEvent? = nil,
        authorRelayListEvents: [NostrEvent] = [],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        hasMoreOlder: Bool = true,
        relaySyncEvents: [NostrRelaySyncEventRecord] = []
    ) {
        self.relays = relays
        self.followedPubkeys = followedPubkeys
        self.noteEvents = noteEvents
        self.metadataEvents = metadataEvents
        self.relayListEvent = relayListEvent
        self.contactListEvent = contactListEvent
        self.authorRelayListEvents = authorRelayListEvents
        self.nip05Resolutions = nip05Resolutions
        self.hasMoreOlder = hasMoreOlder
        self.relaySyncEvents = relaySyncEvents
    }
}
