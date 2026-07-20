import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Timeline rich content resolver")
struct NostrTimelineRichContentResolverTests {
    @Test("Repeated profile references resolve without duplicate-key failure")
    func repeatedProfileReferencesResolveOnce() {
        let pubkey = String(repeating: "a", count: 64)
        let profileReference = NostrRichContentReference.profile(pubkey: pubkey, relays: [])
        let richContent = NostrRichContent(
            displayText: "",
            tokens: [
                .profile(pubkey: pubkey, relays: []),
                .text(" / "),
                .profile(pubkey: pubkey, relays: [])
            ],
            references: [profileReference, profileReference]
        )

        let resolved = NostrTimelineRichContentResolver.resolve(
            richContent,
            eventsByID: [:],
            metadataEvents: [metadataEvent(pubkey: pubkey, displayName: "Alice")],
            nip05Resolutions: [:],
            followedPubkeys: [pubkey]
        )

        #expect(resolved.displayText == "@Alice / @Alice")
        #expect(resolved.profileDisplayNamesByPubkey == [pubkey: "Alice"])
    }

    @Test("Repeated event references resolve without duplicate-key failure")
    func repeatedEventReferencesResolveOnce() {
        let pubkey = String(repeating: "a", count: 64)
        let eventID = String(repeating: "b", count: 64)
        let eventReference = NostrRichContentReference.event(
            eventID: eventID,
            relays: [],
            author: pubkey,
            kind: 1
        )
        let richContent = NostrRichContent(
            displayText: "",
            tokens: [
                .event(eventID: eventID, relays: [], author: pubkey, kind: 1),
                .text(" + "),
                .event(eventID: eventID, relays: [], author: pubkey, kind: 1)
            ],
            references: [eventReference, eventReference]
        )
        let event = NostrEvent(
            id: eventID,
            pubkey: pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "Referenced note",
            sig: ""
        )

        let resolved = NostrTimelineRichContentResolver.resolve(
            richContent,
            eventsByID: [eventID: event],
            metadataEvents: [metadataEvent(pubkey: pubkey, displayName: "Alice")],
            nip05Resolutions: [:],
            followedPubkeys: [pubkey]
        )

        #expect(resolved.displayText == "note:@Alice + note:@Alice")
        #expect(resolved.eventDisplayTextByID == [eventID: "note:@Alice"])
    }

    private func metadataEvent(pubkey: String, displayName: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: "c", count: 64),
            pubkey: pubkey,
            createdAt: 200,
            kind: 0,
            tags: [],
            content: #"{"display_name":"\#(displayName)"}"#,
            sig: ""
        )
    }
}
