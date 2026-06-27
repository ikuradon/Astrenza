import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineQuoteMaterializationPolicy")
struct TimelineQuoteMaterializationPolicyTests {
    private let materializer = FixtureTimelineFeedMaterializer()
    private let boundary = FixtureTimelineRepositoryBoundary()

    @Test("Home quoting note emits one source row and quote render hint")
    func homeQuotingNoteEmitsOneSourceRowAndQuoteRenderHint() throws {
        let output = materializer.materialize(
            sourceEvent(eventID: "quote-source", tags: [["q", "quote-target"]]),
            policy: .home()
        )

        let row = try #require(output.rows.first)
        let hint = try #require(output.quoteRenderHints.first)
        let relation = try #require(output.quoteRelation)

        #expect(output.issues.isEmpty)
        #expect(output.rows.count == 1)
        #expect(output.rows.map(\.itemKey) == ["note:quote-source"])
        #expect(!output.rows.contains { $0.itemKey == "quote:quote-source" })
        #expect(row.sourceEventID == eventID("quote-source"))
        #expect(row.subjectEventID == eventID("quote-source"))
        #expect(row.reason == .author)
        #expect(row.entryID?.rawValue == "note:quote-source")
        #expect(hint.itemKey == "note:quote-source")
        #expect(hint.quoteTargetEventID == eventID("quote-target"))
        #expect(hint.isFallbackCapable)
        #expect(relation.targetEventID == eventID("quote-target"))
        #expect(relation.createsReplyParent == false)
        #expect(relation.createsReplyRoot == false)
        #expect(output.diagnostics.sourceAuthorRowCount == 1)
        #expect(output.diagnostics.quoteRowCount == 0)
        assertLocalOnly(output)
    }

    @Test("Home missing quote target remains fallback capable")
    func homeMissingQuoteTargetRemainsFallbackCapable() throws {
        let output = materializer.materialize(
            sourceEvent(eventID: "missing-quote-source", tags: [["q", "missing-quote-target"]]),
            policy: .home()
        )

        let row = try #require(output.rows.first)
        let hint = try #require(output.quoteRenderHints.first)

        #expect(output.issues.isEmpty)
        #expect(output.rows.map(\.itemKey) == ["note:missing-quote-source"])
        #expect(row.isMissingTargetFallbackCapable == false)
        #expect(hint.quoteTargetEventID == eventID("missing-quote-target"))
        #expect(hint.isFallbackCapable)
        #expect(output.diagnostics.resolveJobDraftCount == 0)
        assertLocalOnly(output)
    }

    @Test("Specialized quote feed emits first-class quote row")
    func specializedQuoteFeedEmitsFirstClassQuoteRow() throws {
        let output = materializer.materialize(
            sourceEvent(eventID: "quote-feed-source", tags: [["q", "quote-feed-target"]]),
            policy: .specializedQuoteFeed()
        )

        let row = try #require(output.rows.first)

        #expect(output.issues.isEmpty)
        #expect(output.rows.count == 1)
        #expect(output.rows.map(\.itemKey) == ["quote:quote-feed-source"])
        #expect(row.sourceEventID == eventID("quote-feed-source"))
        #expect(row.subjectEventID == eventID("quote-feed-target"))
        #expect(row.reason == .quote)
        #expect(row.entryID?.rawValue == "quote:quote-feed-source")
        #expect(row.isMissingTargetFallbackCapable)
        #expect(!output.rows.contains { $0.itemKey == "note:quote-feed-source" })
        #expect(!output.rows.contains { $0.itemKey == "note:quote-feed-target" })
        #expect(output.diagnostics.quoteRowCount == 1)
        #expect(output.diagnostics.resolveJobDraftCount == 0)
        assertLocalOnly(output)
    }

    @Test("Specialized quote feed nil subject means unresolved unavailable")
    func specializedQuoteFeedNilSubjectMeansUnresolvedUnavailable() throws {
        let output = materializer.materialize(
            sourceEvent(eventID: "nil-subject-source", tags: []),
            policy: .specializedQuoteFeed()
        )

        let row = try #require(output.rows.first)

        #expect(output.issues.isEmpty)
        #expect(row.itemKey == "quote:nil-subject-source")
        #expect(row.sourceEventID == eventID("nil-subject-source"))
        #expect(row.subjectEventID == nil)
        #expect(row.reason == .quote)
        #expect(row.reason != .reply)
        #expect(row.isMissingTargetFallbackCapable)
        #expect(output.diagnostics.resolveJobDraftCount == 0)
        assertLocalOnly(output)
    }

    @Test("q tag does not become reply parent or root")
    func qTagDoesNotBecomeReplyParentOrRoot() throws {
        let output = materializer.materialize(
            sourceEvent(eventID: "q-only-source", tags: [["q", "quote-only-target"]]),
            policy: .home()
        )

        let relation = try #require(output.quoteRelation)

        #expect(output.issues.isEmpty)
        #expect(relation.targetEventID == eventID("quote-only-target"))
        #expect(relation.replyParentEventID == nil)
        #expect(relation.replyRootEventID == nil)
        #expect(relation.createsReplyParent == false)
        #expect(relation.createsReplyRoot == false)
        assertLocalOnly(output)
    }

    @Test("Reply relation remains NIP-10 only")
    func replyRelationRemainsNIP10Only() throws {
        let output = materializer.materialize(
            sourceEvent(eventID: "reply-separation-source", tags: [
                ["q", "quote-target"],
                ["e", "reply-root", "", "root"],
                ["e", "reply-parent", "", "reply"]
            ]),
            policy: .home()
        )

        let relation = try #require(output.quoteRelation)

        #expect(output.issues.isEmpty)
        #expect(relation.targetEventID == eventID("quote-target"))
        #expect(relation.replyRootEventID == eventID("reply-root"))
        #expect(relation.replyParentEventID == eventID("reply-parent"))
        #expect(relation.replyParentEventID != relation.targetEventID)
        #expect(relation.createsReplyParent == false)
        #expect(relation.createsReplyRoot == false)
        assertLocalOnly(output)
    }

    @Test("Duplicate Home author and quote rows return typed issue")
    func duplicateHomeAuthorAndQuoteRowsReturnTypedIssue() {
        let output = materializer.materialize(
            sourceEvent(eventID: "duplicate-home-source", tags: [["q", "duplicate-home-target"]]),
            policy: .home(attemptParallelQuoteRow: true)
        )

        #expect(output.rows.map(\.itemKey) == ["note:duplicate-home-source"])
        #expect(output.issues.contains { $0.kind == .duplicateHomeQuoteRow })
        #expect(output.diagnostics.duplicateQuoteRowDedupedCount == 1)
        #expect(output.diagnostics.quoteRowCount == 0)
        assertLocalOnly(output)
    }

    @Test("Specialized quote feed rejects parallel author row without explicit policy")
    func specializedQuoteFeedRejectsParallelAuthorRowWithoutExplicitPolicy() {
        let output = materializer.materialize(
            sourceEvent(eventID: "parallel-source", tags: [["q", "parallel-target"]]),
            policy: .specializedQuoteFeed(attemptSourceAuthorRow: true)
        )

        #expect(output.rows.map(\.itemKey) == ["quote:parallel-source"])
        #expect(output.issues.contains { $0.kind == .parallelSourceReasonWithoutExplicitPolicy })
        #expect(output.diagnostics.sourceAuthorRowCount == 0)
        #expect(output.diagnostics.quoteRowCount == 1)
        assertLocalOnly(output)
    }

    @Test("Quote rows follow repository boundary visibility policy")
    func quoteRowsFollowRepositoryBoundaryVisibilityPolicy() {
        let hidden = materializer.materialize(
            sourceEvent(eventID: "hidden-quote-source", tags: [["q", "hidden-quote-target"]]),
            policy: .specializedQuoteFeed(hiddenReason: "muted")
        )
        let pending = materializer.materialize(
            sourceEvent(eventID: "pending-quote-source", tags: [["q", "pending-quote-target"]]),
            policy: .specializedQuoteFeed(pendingNew: true)
        )
        let collapsed = materializer.materialize(
            sourceEvent(eventID: "collapsed-quote-source", tags: [["q", "collapsed-quote-target"]]),
            policy: .specializedQuoteFeed(collapsed: true)
        )
        let rows = hidden.rows + pending.rows + collapsed.rows

        let defaultWindow = boundary.initialWindow(TimelineInitialWindowRequest(
            feedID: .debugHome,
            rows: rows,
            readState: nil,
            policy: .initialRestore(maxVisibleCount: 10)
        ))
        let explicitPendingWindow = boundary.initialWindow(TimelineInitialWindowRequest(
            feedID: .debugHome,
            rows: rows,
            readState: nil,
            policy: .explicitUserPendingNew(itemKeys: ["quote:pending-quote-source"], maxVisibleCount: 10)
        ))

        #expect(defaultWindow.visibleItemKeys == ["quote:collapsed-quote-source"])
        #expect(defaultWindow.diagnostics.excludedHiddenCount == 1)
        #expect(defaultWindow.diagnostics.excludedPendingNewCount == 1)
        #expect(defaultWindow.diagnostics.collapsedCount == 1)
        #expect(explicitPendingWindow.visibleItemKeys == [
            "quote:collapsed-quote-source",
            "quote:pending-quote-source"
        ])
        #expect(explicitPendingWindow.diagnostics.pendingNewIncludedCount == 1)
        #expect(explicitPendingWindow.diagnostics.pendingNewInclusionReason == .explicitUserAction)
        #expect(defaultWindow.diagnostics.readMarkerChanged == false)
        #expect(explicitPendingWindow.diagnostics.readMarkerChanged == false)
    }

    @Test("Home and specialized quote feed policies keep stable distinct item keys")
    func homeAndSpecializedQuoteFeedPoliciesKeepStableDistinctItemKeys() throws {
        let event = sourceEvent(eventID: "shared-source", tags: [["q", "shared-target"]])
        let home = materializer.materialize(event, policy: .home())
        let specialized = materializer.materialize(event, policy: .specializedQuoteFeed())
        let homeRow = try #require(home.rows.first)
        let specializedRow = try #require(specialized.rows.first)

        #expect(home.issues.isEmpty)
        #expect(specialized.issues.isEmpty)
        #expect(homeRow.itemKey == "note:shared-source")
        #expect(homeRow.reason == .author)
        #expect(homeRow.subjectEventID == eventID("shared-source"))
        #expect(specializedRow.itemKey == "quote:shared-source")
        #expect(specializedRow.reason == .quote)
        #expect(specializedRow.subjectEventID == eventID("shared-target"))
        #expect(homeRow.entryID?.rawValue != specializedRow.entryID?.rawValue)
        assertLocalOnly(home)
        assertLocalOnly(specialized)
    }

    private func sourceEvent(
        eventID: String,
        tags: [[String]]
    ) -> TimelineQuoteMaterializationSourceEvent {
        TimelineQuoteMaterializationSourceEvent(
            eventID: eventID,
            pubkey: "author-pubkey",
            kind: 1,
            tags: tags,
            sortAt: 1_700_000_000
        )
    }

    private func eventID(_ value: String) -> EventID {
        EventID(hex: value)
    }

    private func assertLocalOnly(_ output: TimelineFeedMaterializationOutput) {
        #expect(output.diagnostics.readMarkerChanged == false)
        #expect(output.diagnostics.requiresNetworkWork == false)
        #expect(output.diagnostics.requiresDBWork == false)
        #expect(output.diagnostics.resolveJobDraftCount == 0)
    }
}

private enum TimelineFeedMaterializationFeedKind: String, Codable, Sendable {
    case home
    case specializedQuote
}

private struct TimelineQuoteMaterializationSourceEvent: Equatable, Codable, Sendable {
    var eventID: String
    var pubkey: String
    var kind: Int
    var tags: [[String]]
    var sortAt: Int64
}

private struct TimelineFeedMaterializationDraftPolicy: Equatable, Codable, Sendable {
    var feedKind: TimelineFeedMaterializationFeedKind
    var sourceReason: TimelineRepositoryFeedItemReason
    var attemptParallelQuoteRow: Bool
    var attemptSourceAuthorRow: Bool
    var allowsMultipleRowsPerSourceEvent: Bool
    var hiddenReason: String?
    var collapsed: Bool
    var pendingNew: Bool

    static func home(
        attemptParallelQuoteRow: Bool = false,
        hiddenReason: String? = nil,
        collapsed: Bool = false,
        pendingNew: Bool = false
    ) -> TimelineFeedMaterializationDraftPolicy {
        TimelineFeedMaterializationDraftPolicy(
            feedKind: .home,
            sourceReason: .author,
            attemptParallelQuoteRow: attemptParallelQuoteRow,
            attemptSourceAuthorRow: false,
            allowsMultipleRowsPerSourceEvent: false,
            hiddenReason: hiddenReason,
            collapsed: collapsed,
            pendingNew: pendingNew
        )
    }

    static func specializedQuoteFeed(
        attemptSourceAuthorRow: Bool = false,
        allowsMultipleRowsPerSourceEvent: Bool = false,
        hiddenReason: String? = nil,
        collapsed: Bool = false,
        pendingNew: Bool = false
    ) -> TimelineFeedMaterializationDraftPolicy {
        TimelineFeedMaterializationDraftPolicy(
            feedKind: .specializedQuote,
            sourceReason: .quote,
            attemptParallelQuoteRow: false,
            attemptSourceAuthorRow: attemptSourceAuthorRow,
            allowsMultipleRowsPerSourceEvent: allowsMultipleRowsPerSourceEvent,
            hiddenReason: hiddenReason,
            collapsed: collapsed,
            pendingNew: pendingNew
        )
    }
}

private struct TimelineQuoteRenderHintDraft: Equatable, Codable, Sendable {
    var itemKey: String
    var sourceEventID: EventID
    var quoteTargetEventID: EventID
    var isFallbackCapable: Bool
}

private struct TimelineQuoteRelationDraft: Equatable, Codable, Sendable {
    var sourceEventID: EventID
    var targetEventID: EventID
    var replyParentEventID: EventID?
    var replyRootEventID: EventID?
    var createsReplyParent: Bool
    var createsReplyRoot: Bool
}

private struct TimelineFeedMaterializationDraftIssue: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case duplicateHomeQuoteRow
        case parallelSourceReasonWithoutExplicitPolicy
    }

    var kind: Kind
    var itemKey: String?
    var sourceEventID: EventID?
}

private struct TimelineFeedMaterializationDiagnostics: Equatable, Codable, Sendable {
    var inputCount: Int
    var outputCount: Int
    var quoteRenderHintCount: Int
    var sourceAuthorRowCount: Int
    var quoteRowCount: Int
    var duplicateQuoteRowDedupedCount: Int
    var resolveJobDraftCount: Int
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
}

private struct TimelineFeedMaterializationOutput: Equatable, Codable, Sendable {
    var rows: [TimelineRepositoryFeedItemDraftRow]
    var quoteRenderHints: [TimelineQuoteRenderHintDraft]
    var quoteRelation: TimelineQuoteRelationDraft?
    var issues: [TimelineFeedMaterializationDraftIssue]
    var diagnostics: TimelineFeedMaterializationDiagnostics
}

private struct FixtureTimelineFeedMaterializer: Sendable {
    func materialize(
        _ event: TimelineQuoteMaterializationSourceEvent,
        policy: TimelineFeedMaterializationDraftPolicy
    ) -> TimelineFeedMaterializationOutput {
        let sourceEventID = EventID(hex: event.eventID)
        let quoteTargetID = quoteTarget(in: event)
        let replyRootID = nip10Reference(in: event, marker: "root")
        let replyParentID = nip10Reference(in: event, marker: "reply")
        var rows: [TimelineRepositoryFeedItemDraftRow] = []
        var hints: [TimelineQuoteRenderHintDraft] = []
        var issues: [TimelineFeedMaterializationDraftIssue] = []
        var duplicateQuoteRowDedupedCount = 0

        switch policy.feedKind {
        case .home:
            rows.append(repositoryRow(
                itemKey: "note:\(event.eventID)",
                sourceEventID: sourceEventID,
                subjectEventID: sourceEventID,
                reason: policy.sourceReason,
                event: event,
                policy: policy,
                fallbackCapable: false
            ))

            if let quoteTargetID {
                hints.append(TimelineQuoteRenderHintDraft(
                    itemKey: "note:\(event.eventID)",
                    sourceEventID: sourceEventID,
                    quoteTargetEventID: quoteTargetID,
                    isFallbackCapable: true
                ))
            }

            if policy.attemptParallelQuoteRow {
                issues.append(TimelineFeedMaterializationDraftIssue(
                    kind: .duplicateHomeQuoteRow,
                    itemKey: "quote:\(event.eventID)",
                    sourceEventID: sourceEventID
                ))
                duplicateQuoteRowDedupedCount += 1
            }

        case .specializedQuote:
            rows.append(repositoryRow(
                itemKey: "quote:\(event.eventID)",
                sourceEventID: sourceEventID,
                subjectEventID: quoteTargetID,
                reason: .quote,
                event: event,
                policy: policy,
                fallbackCapable: true
            ))

            if policy.attemptSourceAuthorRow && !policy.allowsMultipleRowsPerSourceEvent {
                issues.append(TimelineFeedMaterializationDraftIssue(
                    kind: .parallelSourceReasonWithoutExplicitPolicy,
                    itemKey: "note:\(event.eventID)",
                    sourceEventID: sourceEventID
                ))
            } else if policy.attemptSourceAuthorRow {
                rows.append(repositoryRow(
                    itemKey: "note:\(event.eventID)",
                    sourceEventID: sourceEventID,
                    subjectEventID: sourceEventID,
                    reason: .author,
                    event: event,
                    policy: policy,
                    fallbackCapable: false
                ))
            }
        }

        let relation = quoteTargetID.map { targetID in
            TimelineQuoteRelationDraft(
                sourceEventID: sourceEventID,
                targetEventID: targetID,
                replyParentEventID: replyParentID,
                replyRootEventID: replyRootID,
                createsReplyParent: false,
                createsReplyRoot: false
            )
        }

        return TimelineFeedMaterializationOutput(
            rows: rows,
            quoteRenderHints: hints,
            quoteRelation: relation,
            issues: issues,
            diagnostics: TimelineFeedMaterializationDiagnostics(
                inputCount: 1,
                outputCount: rows.count,
                quoteRenderHintCount: hints.count,
                sourceAuthorRowCount: rows.filter { $0.reason == .author }.count,
                quoteRowCount: rows.filter { $0.reason == .quote }.count,
                duplicateQuoteRowDedupedCount: duplicateQuoteRowDedupedCount,
                resolveJobDraftCount: 0,
                readMarkerChanged: false,
                requiresNetworkWork: false,
                requiresDBWork: false
            )
        )
    }

    private func repositoryRow(
        itemKey: String,
        sourceEventID: EventID,
        subjectEventID: EventID?,
        reason: TimelineRepositoryFeedItemReason,
        event: TimelineQuoteMaterializationSourceEvent,
        policy: TimelineFeedMaterializationDraftPolicy,
        fallbackCapable: Bool
    ) -> TimelineRepositoryFeedItemDraftRow {
        TimelineRepositoryFeedItemDraftRow(
            itemKey: itemKey,
            sourceEventID: sourceEventID,
            subjectEventID: subjectEventID,
            reason: reason,
            actorPubkey: event.pubkey,
            sortAt: event.sortAt,
            tieBreakID: event.eventID,
            hiddenReason: policy.hiddenReason,
            collapsed: policy.collapsed,
            pendingNew: policy.pendingNew,
            isMissingTargetFallbackCapable: fallbackCapable
        )
    }

    private func quoteTarget(in event: TimelineQuoteMaterializationSourceEvent) -> EventID? {
        event.tags
            .first { $0.count >= 2 && $0[0] == "q" && !$0[1].isEmpty }
            .map { EventID(hex: $0[1]) }
    }

    private func nip10Reference(
        in event: TimelineQuoteMaterializationSourceEvent,
        marker: String
    ) -> EventID? {
        event.tags
            .last { tag in
                tag.count >= 2
                    && tag[0] == "e"
                    && tag.contains(marker)
                    && !tag[1].isEmpty
            }
            .map { EventID(hex: $0[1]) }
    }
}
