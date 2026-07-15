import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline local mutation interaction workflow")
@MainActor
struct HomeLocalMutationInteractionTests {
    @Test("Mute request and ordered rematerialization actions cross the boundary")
    func muteRoutesPersistenceAndSuccessActions() throws {
        let fixture = LocalMutationInteractionFixture()
        let accountID = try #require(fixture.accountID)

        fixture.workflow.perform(
            .muteAuthor(authorPubkey: fixture.authorPubkey),
            context: fixture.context
        )

        #expect(fixture.handler.calls == [
            .muteAuthor(
                accountID: accountID,
                authorPubkey: fixture.authorPubkey,
                timestamp: fixture.timestamp
            )
        ])
        #expect(fixture.probe.actions == [
            .invalidateListEntries,
            .materializeEntries
        ])
    }

    @Test("Bookmark persists without rematerializing the timeline")
    func bookmarkRoutesPersistenceWithoutSuccessActions() throws {
        let fixture = LocalMutationInteractionFixture()
        let accountID = try #require(fixture.accountID)

        fixture.workflow.perform(
            .bookmark(eventID: fixture.eventID),
            context: fixture.context
        )

        #expect(fixture.handler.calls == [
            .bookmark(
                accountID: accountID,
                eventID: fixture.eventID,
                timestamp: fixture.timestamp
            )
        ])
        #expect(fixture.probe.actions.isEmpty)
    }

    @Test(
        "Mutation-specific persistence failures become the existing phase",
        arguments: [
            LocalMutationFailureCase(
                intent: .muteAuthor(authorPubkey: "author"),
                title: "Mute"
            ),
            LocalMutationFailureCase(
                intent: .bookmark(eventID: "event"),
                title: "Bookmark"
            )
        ]
    )
    func failureRoutesMutationSpecificPhase(
        failureCase: LocalMutationFailureCase
    ) {
        let fixture = LocalMutationInteractionFixture(
            error: LocalMutationInteractionError.unavailable
        )

        fixture.workflow.perform(
            failureCase.intent,
            context: fixture.context
        )

        #expect(fixture.probe.actions == [
            .setPhase(.failed(
                "\(failureCase.title) failed: local mutation unavailable"
            ))
        ])
    }

    @Test("Missing account suppresses persistence, time, and application effects")
    func missingAccountIsNoOp() {
        let fixture = LocalMutationInteractionFixture(accountID: nil)

        fixture.workflow.perform(
            .muteAuthor(authorPubkey: fixture.authorPubkey),
            context: fixture.context
        )

        #expect(fixture.handler.calls.isEmpty)
        #expect(fixture.probe.timestampRequestCount == 0)
        #expect(fixture.probe.actions.isEmpty)
    }
}

struct LocalMutationFailureCase: Sendable,
    CustomTestStringConvertible {
    let intent: HomeTimelineLocalMutationIntent
    let title: String

    var testDescription: String {
        title
    }
}

private enum LocalMutationInteractionCall: Equatable {
    case muteAuthor(
        accountID: String,
        authorPubkey: String,
        timestamp: Int
    )
    case bookmark(accountID: String, eventID: String, timestamp: Int)
}

@MainActor
private final class LocalMutationInteractionHandlerSpy:
    HomeTimelineLocalMutationHandling {
    private let error: (any Error)?
    private(set) var calls: [LocalMutationInteractionCall] = []

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func muteAuthor(
        accountID: String,
        authorPubkey: String,
        at timestamp: Int
    ) throws -> NostrFilterRuleRecord {
        calls.append(.muteAuthor(
            accountID: accountID,
            authorPubkey: authorPubkey,
            timestamp: timestamp
        ))
        if let error { throw error }
        return NostrFilterRuleRecord(
            ruleID: "rule",
            accountID: accountID,
            kind: .mutedPubkey,
            value: authorPubkey,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    func bookmarkPost(
        accountID: String,
        eventID: String,
        at timestamp: Int
    ) throws -> NostrLocalBookmarkRecord {
        calls.append(.bookmark(
            accountID: accountID,
            eventID: eventID,
            timestamp: timestamp
        ))
        if let error { throw error }
        return NostrLocalBookmarkRecord(
            accountID: accountID,
            eventID: eventID,
            createdAt: timestamp
        )
    }
}

@MainActor
private final class LocalMutationInteractionProbe {
    private let timestamp: Int
    private(set) var timestampRequestCount = 0
    private(set) var actions: [HomeTimelineLocalMutationStoreAction] = []

    init(timestamp: Int) {
        self.timestamp = timestamp
    }

    func nextTimestamp() -> Int {
        timestampRequestCount += 1
        return timestamp
    }

    var effects: HomeLocalMutationInteractionEffects {
        HomeLocalMutationInteractionEffects(
            apply: { [self] action in
                actions.append(action)
            }
        )
    }
}

@MainActor
private struct LocalMutationInteractionFixture {
    let accountID: String?
    let authorPubkey = String(repeating: "b", count: 64)
    let eventID = String(repeating: "1", count: 64)
    let timestamp = 123
    let handler: LocalMutationInteractionHandlerSpy
    let probe: LocalMutationInteractionProbe
    let workflow: HomeLocalMutationInteractionWorkflow

    init(
        accountID: String? = String(repeating: "a", count: 64),
        error: (any Error)? = nil
    ) {
        self.accountID = accountID
        let handler = LocalMutationInteractionHandlerSpy(error: error)
        let probe = LocalMutationInteractionProbe(timestamp: timestamp)
        self.handler = handler
        self.probe = probe
        workflow = HomeLocalMutationInteractionWorkflow(
            localMutation: handler,
            currentTimestamp: probe.nextTimestamp
        )
    }

    var context: HomeLocalMutationInteractionContext {
        HomeLocalMutationInteractionContext(
            state: HomeLocalMutationInteractionState(accountID: accountID),
            effects: probe.effects
        )
    }
}

private enum LocalMutationInteractionError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "local mutation unavailable"
    }
}
