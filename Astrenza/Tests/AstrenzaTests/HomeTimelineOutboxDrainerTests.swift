import Testing
@testable import Astrenza

@Suite("Home timeline outbox drainer")
struct HomeTimelineOutboxDrainerTests {
    @Test("Duplicate relay acknowledgements count as accepted delivery")
    func duplicateAcknowledgement() {
        #expect(HomeTimelineOutboxDrainer.isDuplicateAcknowledgment(" Duplicate: already saved "))
        #expect(!HomeTimelineOutboxDrainer.isDuplicateAcknowledgment("blocked: denied"))
        #expect(!HomeTimelineOutboxDrainer.isDuplicateAcknowledgment(nil))
    }

    @Test("Permanent relay rejection prefixes stop retries")
    func terminalRejections() {
        for message in [
            "auth-required: challenge",
            "blocked: denied",
            "invalid: event",
            "payment-required: invoice",
            "pow: insufficient",
            "restricted: policy"
        ] {
            #expect(HomeTimelineOutboxDrainer.isTerminalRejection(message))
        }
        #expect(!HomeTimelineOutboxDrainer.isTerminalRejection("rate-limited: retry later"))
        #expect(!HomeTimelineOutboxDrainer.isTerminalRejection(nil))
    }
}
