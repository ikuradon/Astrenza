import Testing
@testable import AstrenzaCore

@Suite("Nostr timeline index policy")
struct NostrTimelineIndexPolicyTests {
    @Test("Timeline index policy keeps anchor gap and recent entries")
    func keepsProtectedEntries() {
        let policy = NostrTimelineIndexPolicy(
            recentLimit: 3,
            anchorRadius: 1,
            retainedAgeSeconds: 60
        )
        let entries = [
            NostrTimelineIndexCandidate(eventID: "newest", sortTimestamp: 500, insertedAt: 500, gapBefore: false, gapAfter: false),
            NostrTimelineIndexCandidate(eventID: "gap-newer", sortTimestamp: 400, insertedAt: 400, gapBefore: false, gapAfter: true),
            NostrTimelineIndexCandidate(eventID: "anchor", sortTimestamp: 300, insertedAt: 300, gapBefore: false, gapAfter: false),
            NostrTimelineIndexCandidate(eventID: "gap-older", sortTimestamp: 200, insertedAt: 200, gapBefore: true, gapAfter: false),
            NostrTimelineIndexCandidate(eventID: "old", sortTimestamp: 100, insertedAt: 100, gapBefore: false, gapAfter: false)
        ]

        let retained = policy.retainedEventIDs(
            from: entries,
            anchorEventID: "anchor",
            now: 520
        )

        #expect(retained.contains("newest"))
        #expect(retained.contains("gap-newer"))
        #expect(retained.contains("anchor"))
        #expect(retained.contains("gap-older"))
        #expect(!retained.contains("old"))
    }

    @Test("Timeline index policy keeps age protected entries outside recent window")
    func keepsAgeProtectedEntries() {
        let policy = NostrTimelineIndexPolicy(
            recentLimit: 1,
            anchorRadius: 0,
            retainedAgeSeconds: 100
        )
        let entries = [
            NostrTimelineIndexCandidate(eventID: "newest", sortTimestamp: 500, insertedAt: 500, gapBefore: false, gapAfter: false),
            NostrTimelineIndexCandidate(eventID: "recent-write", sortTimestamp: 100, insertedAt: 480, gapBefore: false, gapAfter: false),
            NostrTimelineIndexCandidate(eventID: "old-write", sortTimestamp: 90, insertedAt: 300, gapBefore: false, gapAfter: false)
        ]

        let retained = policy.retainedEventIDs(
            from: entries,
            anchorEventID: nil,
            now: 520
        )

        #expect(retained == ["newest", "recent-write"])
    }
}
