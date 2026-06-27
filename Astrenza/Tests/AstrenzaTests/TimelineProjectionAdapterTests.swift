import DesignSystem
import Foundation
import Testing
@testable import Astrenza

@Suite("Timeline projection adapter")
struct TimelineProjectionAdapterTests {
    private let adapter = FixtureBackedTimelineProjectionAdapter()
    private let scenarios = TimelineProjectionFixtureBuilder.allScenarios

    @Test("Every Phase 6.0 fixture is accepted by the fixture backed adapter")
    func everyPhase60FixtureIsAcceptedByFixtureBackedAdapter() throws {
        var acceptedCount = 0

        for scenario in scenarios {
            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))

            #expect(output.issues.isEmpty, "Unexpected adapter issues for \(scenario.name): \(output.issues)")
            #expect(output.scenarioName == scenario.name)
            #expect(output.entryID == scenario.expectedOutput.identity.entryID)
            #expect(output.itemKey == scenario.expectedOutput.identity.itemKey)
            #expect(output.sourceEventID == scenario.expectedOutput.identity.sourceEventID)
            #expect(output.subjectEventID == scenario.expectedOutput.identity.subjectEventID)
            #expect(output.sortAt == scenario.expectedOutput.identity.sortAt)
            #expect(output.tieBreakID == scenario.expectedOutput.identity.tieBreakID)
            #expect(output.resolveExpectations == scenario.expectedOutput.resolveExpectations)
            #expect(output.diagnostics.validatedByContractValidator)
            acceptedCount += 1
        }

        #expect(acceptedCount == TimelineProjectionFixtureBuilder.allScenarios.count)
    }

    @Test("Adapter output preserves source event and subject event distinction")
    func adapterOutputPreservesSourceEventAndSubjectEventDistinction() throws {
        let scenario = try fixture(named: "repost_target_pending_to_resolved")
        let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))

        let sourceEventID = try #require(output.sourceEventID)
        let subjectEventID = try #require(output.subjectEventID)

        #expect(sourceEventID == scenario.expectedOutput.identity.sourceEventID)
        #expect(subjectEventID == scenario.expectedOutput.identity.subjectEventID)
        #expect(sourceEventID != subjectEventID)
    }

    @Test("Delayed resolve transitions produce reconfigure mutation without delete or insert")
    func delayedResolveTransitionsProduceReconfigureMutationWithoutDeleteOrInsert() throws {
        for scenario in scenarios where scenario.hasDelayedResolveTransition {
            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
            let mutation = try #require(output.mutationExpectation)

            #expect(mutation.style == .reconfigure, "Unexpected mutation style for \(scenario.name)")
            #expect(mutation.initialEntryID == scenario.expectedOutput.mutation.initialEntryID)
            #expect(mutation.finalEntryID == scenario.expectedOutput.mutation.finalEntryID)
            #expect(mutation.insertedIDs.isEmpty)
            #expect(mutation.deletedIDs.isEmpty)
            #expect(!mutation.allowsDeleteInsertForDelayedResolve)
            #expect(!mutation.readMarkerChanged)
        }
    }

    @Test("Resolve enrichment targets never produce delete or insert mutation")
    func resolveEnrichmentTargetsNeverProduceDeleteOrInsertMutation() throws {
        let enrichmentTargets: Set<TimelineDelayedResolveTarget> = [
            .profile,
            .bodyMention,
            .media,
            .linkPreviewOGP,
            .repostTarget,
            .quoteTarget,
            .replyParentRoot,
            .stats,
            .publishStatePlaceholder
        ]

        for scenario in scenarios {
            let touchesEnrichmentTarget = scenario.expectedOutput.resolveExpectations.contains { expectation in
                enrichmentTargets.contains(expectation.target)
            }
            guard touchesEnrichmentTarget else {
                continue
            }

            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
            let mutation = try #require(output.mutationExpectation)

            #expect(mutation.style == .reconfigure, "Unexpected mutation style for \(scenario.name)")
            #expect(mutation.insertedIDs.isEmpty)
            #expect(mutation.deletedIDs.isEmpty)
        }
    }

    @Test("Failed or blocked resolve returns fallback while keeping source note visible")
    func failedOrBlockedResolveReturnsFallbackWhileKeepingSourceNoteVisible() throws {
        for scenario in scenarios where scenario.expectedOutput.resolveExpectations.contains(where: \.requiresFallback) {
            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
            let fallback = try #require(output.fallback)
            let visibility = try #require(output.visibilityDecision)

            #expect(fallback.keepsSourceNoteVisible)
            #expect(visibility.removesSourceNote == false)
            #expect(visibility.fallbackMode == scenario.expectedOutput.fallback.mode)
        }
    }

    @Test("Quote target and reply parent boundaries remain distinct")
    func quoteTargetAndReplyParentBoundariesRemainDistinct() throws {
        let quote = adapter.project(TimelineProjectionAdapterInput(
            scenario: try fixture(named: "quote_target_must_not_create_reply_relation")
        ))
        let quoteMutation = try #require(quote.mutationExpectation)
        let quoteLayout = try #require(quote.layoutDecision)

        #expect(!quoteMutation.quoteCreatesReplyRelation)
        #expect(quoteLayout.contract.quoteMode == .collapsedCard)
        #expect(quoteLayout.contract.replyHeaderMode == .absent)

        let reply = adapter.project(TimelineProjectionAdapterInput(
            scenario: try fixture(named: "reply_parent_pending_to_resolved_headerOnly")
        ))
        let replyLayout = try #require(reply.layoutDecision)

        #expect(replyLayout.contract.rowKind == .home)
        #expect(replyLayout.contract.replyHeaderMode == .oneLine)
        #expect(!replyLayout.contract.allowsInlineParentPreviewInHome)
    }

    @Test("Pending new stays hidden until explicit user action")
    func pendingNewStaysHiddenUntilExplicitUserAction() throws {
        let scenario = try fixture(named: "pending_new_not_visible_until_user_action")
        let entryID = scenario.expectedOutput.identity.entryID

        let blocked = adapter.project(TimelineProjectionAdapterInput(
            scenario: scenario,
            currentVisibleEntryIDs: [],
            pendingNewEntryIDs: [entryID],
            userActionAllowsPendingNewInsertion: false
        ))
        let blockedVisibility = try #require(blocked.visibilityDecision)
        let blockedMutation = try #require(blocked.mutationExpectation)

        #expect(!blockedVisibility.includedInVisibleSnapshot)
        #expect(!blockedVisibility.pendingNewVisible)
        #expect(blockedMutation.style == .none)
        #expect(!blocked.diagnostics.pendingNewVisible)

        let allowed = adapter.project(TimelineProjectionAdapterInput(
            scenario: scenario,
            currentVisibleEntryIDs: [],
            pendingNewEntryIDs: [entryID],
            userActionAllowsPendingNewInsertion: true
        ))
        let allowedVisibility = try #require(allowed.visibilityDecision)
        let allowedMutation = try #require(allowed.mutationExpectation)

        #expect(allowedVisibility.includedInVisibleSnapshot)
        #expect(allowedVisibility.pendingNewVisible)
        #expect(allowedMutation.style == .insertOnlyForExplicitUserPendingNewAction)
        #expect(allowedMutation.insertedIDs == [entryID])
        #expect(allowed.diagnostics.pendingNewVisible)
    }

    @Test("Publish state placeholder requires no remote work")
    func publishStatePlaceholderRequiresNoRemoteWork() throws {
        let output = adapter.project(TimelineProjectionAdapterInput(
            scenario: try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange")
        ))

        #expect(output.resolveExpectations.allSatisfy { expectation in
            expectation.target == .publishStatePlaceholder && !expectation.requiresRemoteWork
        })
        #expect(!output.diagnostics.requiresNetworkWork)
        #expect(!output.diagnostics.requiresDBWork)
    }

    @Test("Adapter diagnostics keep read marker network and database work disabled")
    func adapterDiagnosticsKeepReadMarkerNetworkAndDatabaseWorkDisabled() {
        for scenario in scenarios {
            let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))

            #expect(!output.diagnostics.readMarkerChanged)
            #expect(!output.diagnostics.requiresNetworkWork)
            #expect(!output.diagnostics.requiresDBWork)
        }
    }

    @Test("Adapter uses validator and rejects invalid contract scenarios")
    func adapterUsesValidatorAndRejectsInvalidContractScenarios() throws {
        var unstableIdentity = try fixture(named: "ogp_pending_to_resolved")
        unstableIdentity.expectedOutput.identity.itemKey += ":resolved"
        unstableIdentity.expectedOutput.mutation.finalEntryID = unstableIdentity.expectedOutput.identity.entryID
        expectContractIssue(.unstableIdentity, in: unstableIdentity)

        var readMarkerChanged = try fixture(named: "profile_missing_to_resolved_headerOnly")
        readMarkerChanged.expectedOutput.mutation.readMarkerChanged = true
        expectContractIssue(.readMarkerMustNotChange, in: readMarkerChanged)

        var pendingNewViolation = try fixture(named: "pending_new_not_visible_until_user_action")
        pendingNewViolation.expectedOutput.visibility.includedInVisibleSnapshot = true
        pendingNewViolation.expectedOutput.mutation.pendingNewInsertedIntoVisibleSnapshot = true
        expectContractIssue(.pendingNewMustWaitForUserAction, in: pendingNewViolation)
    }

    @Test("Adapter covers every delayed resolve target and resolve state")
    func adapterCoversEveryDelayedResolveTargetAndResolveState() {
        let outputs = scenarios.map { scenario in
            adapter.project(TimelineProjectionAdapterInput(scenario: scenario))
        }
        let targets = Set(outputs.flatMap { output in
            output.resolveExpectations.map(\.target)
        })
        let states = Set(outputs.flatMap { output in
            output.resolveExpectations.flatMap { expectation in
                [expectation.initialState, expectation.expectedState]
            }
        })

        #expect(targets.isSuperset(of: Set(TimelineDelayedResolveTarget.allCases)))
        #expect(states.isSuperset(of: Set(TimelineProjectionResolveState.allCases)))
    }

    @Test("Adapter models are codable equatable and sendable")
    func adapterModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineProjectionAdapterInput.self)
        assertSendable(TimelineProjectionAdapterOutput.self)
        assertSendable(TimelineProjectionAdapterIssue.self)
        assertSendable(TimelineProjectionAdapterDiagnostics.self)
        assertSendable(TimelineProjectionMutationExpectation.self)
        assertSendable(TimelineProjectionLayoutDecision.self)
        assertSendable(TimelineProjectionVisibilityDecision.self)

        let input = TimelineProjectionAdapterInput(
            scenario: try fixture(named: "ogp_pending_to_resolved"),
            surface: .home,
            currentVisibleEntryIDs: [TimelineEntryID(rawValue: "home:visible")],
            pendingNewEntryIDs: [],
            userActionAllowsPendingNewInsertion: false
        )
        let output = adapter.project(input)

        try assertCodableRoundTrip(input)
        try assertCodableRoundTrip(output)
        try assertCodableRoundTrip(try #require(output.mutationExpectation))
        try assertCodableRoundTrip(try #require(output.layoutDecision))
        try assertCodableRoundTrip(try #require(output.visibilityDecision))
        try assertCodableRoundTrip(output.diagnostics)
    }

    private func fixture(named name: String) throws -> TimelineProjectionScenario {
        try #require(TimelineProjectionFixtureBuilder.scenario(named: name))
    }

    private func expectContractIssue(
        _ rule: TimelineProjectionValidationIssue.Rule,
        in scenario: TimelineProjectionScenario
    ) {
        let output = adapter.project(TimelineProjectionAdapterInput(scenario: scenario))

        #expect(output.entryID == nil)
        #expect(output.issues.contains { issue in
            issue.kind == .contractValidation && issue.contractRule == rule
        }, "Expected \(rule), got \(output.issues)")
        #expect(output.diagnostics.validatedByContractValidator)
        #expect(output.diagnostics.contractIssueCount > 0)
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    private func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)

        #expect(decoded == value)
    }
}

private struct TimelineLegacyEntryRecordDraft: Codable, Equatable, Sendable {
    var accountID: String
    var timelineKey: String
    var eventID: String?
    var sortTimestamp: Int64
    var source: String
    var insertedAt: Int64
    var gapBefore: Bool
    var gapAfter: Bool
    var pendingNew: Bool
    var visibility: TimelineFeedItemDraftVisibility

    init(
        accountID: String,
        timelineKey: String,
        eventID: String?,
        sortTimestamp: Int64,
        source: String,
        insertedAt: Int64,
        gapBefore: Bool = false,
        gapAfter: Bool = false,
        pendingNew: Bool = false,
        visibility: TimelineFeedItemDraftVisibility = .visible
    ) {
        self.accountID = accountID
        self.timelineKey = timelineKey
        self.eventID = eventID
        self.sortTimestamp = sortTimestamp
        self.source = source
        self.insertedAt = insertedAt
        self.gapBefore = gapBefore
        self.gapAfter = gapAfter
        self.pendingNew = pendingNew
        self.visibility = visibility
    }
}

private struct TimelineLegacyEventRecordDraft: Codable, Equatable, Sendable {
    var eventID: String
    var pubkey: String
    var kind: Int
    var tags: [[String]]
}

private enum TimelineFeedItemDraftReason: String, CaseIterable, Codable, Sendable {
    case author
    case reply
    case repost
    case quote
    case mention
    case reaction
    case zap
    case follow
    case manual
}

private enum TimelineFeedItemDraftVisibility: Equatable, Codable, Sendable {
    case visible
    case hidden(reason: String)
    case mutedCollapsed
}

private enum TimelineFeedItemDraftFilterPolicy: String, Codable, Sendable {
    case sourceOnly
    case deferToFutureMaterializer
}

private enum TimelineFeedItemDraftResolveCandidateKind: String, Codable, Sendable {
    case profile
    case media
    case linkPreviewOGP
    case repostTarget
    case quoteTarget
    case replyParentRoot
}

private struct TimelineFeedItemDraftResolveCandidate: Equatable, Codable, Sendable {
    var kind: TimelineFeedItemDraftResolveCandidateKind
    var targetKey: String
}

private struct TimelineFeedItemDraft: Equatable, Codable, Sendable {
    var accountID: String
    var timelineKey: String
    var feedID: Int64?
    var itemKey: String
    var sourceEventID: String
    var subjectEventID: String?
    var reason: TimelineFeedItemDraftReason
    var actorPubkey: String?
    var sortAt: Int64
    var tieBreakID: String
    var hiddenReason: String?
    var collapsed: Bool
    var pendingNew: Bool
    var insertedAt: Int64
    var visibility: TimelineFeedItemDraftVisibility
    var filterPolicy: TimelineFeedItemDraftFilterPolicy
    var futureResolveCandidates: [TimelineFeedItemDraftResolveCandidate]
}

private struct TimelineFeedItemDraftIssue: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case missingEventID
        case missingEvent
        case duplicateItemKey
        case unsupportedSourceKind
    }

    var kind: Kind
    var eventID: String?
    var eventKind: Int?

    init(kind: Kind, eventID: String? = nil, eventKind: Int? = nil) {
        self.kind = kind
        self.eventID = eventID
        self.eventKind = eventKind
    }
}

private struct TimelineFeedItemDraftDiagnostics: Equatable, Codable, Sendable {
    var inputCount: Int
    var outputCount: Int
    var droppedCount: Int
    var unsupportedKindCount: Int
    var pendingNewCount: Int
    var unresolvedTargetCount: Int
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
}

private struct TimelineFeedItemDraftAdapterOutput: Equatable, Codable, Sendable {
    var drafts: [TimelineFeedItemDraft]
    var issues: [TimelineFeedItemDraftIssue]
    var diagnostics: TimelineFeedItemDraftDiagnostics
}

private struct TimelineFeedItemDraftAdapter: Sendable {
    func map(
        entries: [TimelineLegacyEntryRecordDraft],
        events: [String: TimelineLegacyEventRecordDraft]
    ) -> TimelineFeedItemDraftAdapterOutput {
        var drafts: [TimelineFeedItemDraft] = []
        var issues: [TimelineFeedItemDraftIssue] = []
        var seenItemKeys: Set<String> = []
        var droppedCount = 0
        var unsupportedKindCount = 0

        for entry in entries {
            guard let eventID = entry.eventID, !eventID.isEmpty else {
                issues.append(TimelineFeedItemDraftIssue(kind: .missingEventID))
                droppedCount += 1
                continue
            }

            guard let event = events[eventID] else {
                issues.append(TimelineFeedItemDraftIssue(kind: .missingEvent, eventID: eventID))
                droppedCount += 1
                continue
            }

            guard isSupportedSourceEventKind(event.kind) else {
                issues.append(TimelineFeedItemDraftIssue(
                    kind: .unsupportedSourceKind,
                    eventID: eventID,
                    eventKind: event.kind
                ))
                droppedCount += 1
                unsupportedKindCount += 1
                continue
            }

            let draft = draft(for: entry, event: event, events: events)
            guard seenItemKeys.insert(draft.itemKey).inserted else {
                issues.append(TimelineFeedItemDraftIssue(kind: .duplicateItemKey, eventID: eventID))
                droppedCount += 1
                continue
            }

            drafts.append(draft)
        }

        let sortedDrafts = sortForVisibleWindow(drafts)
        let unresolvedTargetCount = sortedDrafts.reduce(0) { count, draft in
            count + draft.futureResolveCandidates.count
        }
        let diagnostics = TimelineFeedItemDraftDiagnostics(
            inputCount: entries.count,
            outputCount: sortedDrafts.count,
            droppedCount: droppedCount,
            unsupportedKindCount: unsupportedKindCount,
            pendingNewCount: sortedDrafts.filter(\.pendingNew).count,
            unresolvedTargetCount: unresolvedTargetCount,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresDBWork: false
        )

        return TimelineFeedItemDraftAdapterOutput(
            drafts: sortedDrafts,
            issues: issues,
            diagnostics: diagnostics
        )
    }

    static func visibleWindowDrafts(
        _ drafts: [TimelineFeedItemDraft],
        explicitPendingNewItemKeys: Set<String> = []
    ) -> [TimelineFeedItemDraft] {
        sortForVisibleWindow(drafts).filter { draft in
            draft.hiddenReason == nil
                && (!draft.pendingNew || explicitPendingNewItemKeys.contains(draft.itemKey))
        }
    }

    private func draft(
        for entry: TimelineLegacyEntryRecordDraft,
        event: TimelineLegacyEventRecordDraft,
        events: [String: TimelineLegacyEventRecordDraft]
    ) -> TimelineFeedItemDraft {
        let shape = draftShape(for: event, events: events)
        let visibility = visibilityFields(from: entry.visibility)

        return TimelineFeedItemDraft(
            accountID: entry.accountID,
            timelineKey: entry.timelineKey,
            feedID: nil,
            itemKey: shape.itemKey,
            sourceEventID: event.eventID,
            subjectEventID: shape.subjectEventID,
            reason: shape.reason,
            actorPubkey: event.pubkey,
            sortAt: entry.sortTimestamp,
            tieBreakID: event.eventID,
            hiddenReason: visibility.hiddenReason,
            collapsed: visibility.collapsed,
            pendingNew: entry.pendingNew,
            insertedAt: entry.insertedAt,
            visibility: entry.visibility,
            filterPolicy: shape.filterPolicy,
            futureResolveCandidates: shape.futureResolveCandidates
        )
    }

    private func draftShape(
        for event: TimelineLegacyEventRecordDraft,
        events: [String: TimelineLegacyEventRecordDraft]
    ) -> DraftShape {
        if event.kind == 6 {
            let targetID = lastEventReference(in: event.tags)
            return DraftShape(
                itemKey: "repost:\(event.eventID)",
                subjectEventID: targetID,
                reason: .repost,
                filterPolicy: .sourceOnly,
                futureResolveCandidates: unresolvedCandidate(
                    kind: .repostTarget,
                    targetKey: targetID,
                    events: events
                )
            )
        }

        var candidates = enrichmentCandidates(for: event, events: events)
        let replyParentID = replyReference(in: event.tags)
        if event.kind == 1, let replyParentID {
            appendUnique(
                TimelineFeedItemDraftResolveCandidate(kind: .replyParentRoot, targetKey: replyParentID),
                to: &candidates
            )
            return DraftShape(
                itemKey: "note:\(event.eventID)",
                subjectEventID: event.eventID,
                reason: .reply,
                filterPolicy: .deferToFutureMaterializer,
                futureResolveCandidates: candidates
            )
        }

        return DraftShape(
            itemKey: "note:\(event.eventID)",
            subjectEventID: event.eventID,
            reason: .author,
            filterPolicy: .sourceOnly,
            futureResolveCandidates: candidates
        )
    }

    private func enrichmentCandidates(
        for event: TimelineLegacyEventRecordDraft,
        events: [String: TimelineLegacyEventRecordDraft]
    ) -> [TimelineFeedItemDraftResolveCandidate] {
        var candidates: [TimelineFeedItemDraftResolveCandidate] = []

        for tag in event.tags {
            guard let marker = tag.first else { continue }

            switch marker {
            case "p":
                if let target = tagValue(tag) {
                    appendUnique(
                        TimelineFeedItemDraftResolveCandidate(kind: .profile, targetKey: target),
                        to: &candidates
                    )
                }
            case "r":
                if let target = tagValue(tag) {
                    appendUnique(
                        TimelineFeedItemDraftResolveCandidate(kind: .linkPreviewOGP, targetKey: target),
                        to: &candidates
                    )
                }
            case "imeta":
                if let target = imetaURL(in: tag) {
                    appendUnique(
                        TimelineFeedItemDraftResolveCandidate(kind: .media, targetKey: target),
                        to: &candidates
                    )
                }
            case "q":
                if let target = tagValue(tag), events[target] == nil {
                    appendUnique(
                        TimelineFeedItemDraftResolveCandidate(kind: .quoteTarget, targetKey: target),
                        to: &candidates
                    )
                }
            default:
                continue
            }
        }

        return candidates
    }

    private func unresolvedCandidate(
        kind: TimelineFeedItemDraftResolveCandidateKind,
        targetKey: String?,
        events: [String: TimelineLegacyEventRecordDraft]
    ) -> [TimelineFeedItemDraftResolveCandidate] {
        guard let targetKey, events[targetKey] == nil else { return [] }
        return [TimelineFeedItemDraftResolveCandidate(kind: kind, targetKey: targetKey)]
    }

    private func visibilityFields(
        from visibility: TimelineFeedItemDraftVisibility
    ) -> (hiddenReason: String?, collapsed: Bool) {
        switch visibility {
        case .visible:
            return (nil, false)
        case .hidden(let reason):
            return (reason, false)
        case .mutedCollapsed:
            return (nil, true)
        }
    }

    private func lastEventReference(in tags: [[String]]) -> String? {
        tags.last { tag in
            tag.count >= 2 && tag[0] == "e"
        }.flatMap(tagValue)
    }

    private func replyReference(in tags: [[String]]) -> String? {
        tags.last { tag in
            tag.count >= 2
                && tag[0] == "e"
                && tag.contains("reply")
        }.flatMap(tagValue)
    }

    private func tagValue(_ tag: [String]) -> String? {
        guard tag.count >= 2, !tag[1].isEmpty else { return nil }
        return tag[1]
    }

    private func imetaURL(in tag: [String]) -> String? {
        tag.lazy.compactMap { component -> String? in
            guard component.hasPrefix("url ") else { return nil }
            let value = String(component.dropFirst(4))
            return value.isEmpty ? nil : value
        }.first
    }

    private func isSupportedSourceEventKind(_ kind: Int) -> Bool {
        kind == 1 || kind == 6
    }

    private func appendUnique(
        _ candidate: TimelineFeedItemDraftResolveCandidate,
        to candidates: inout [TimelineFeedItemDraftResolveCandidate]
    ) {
        guard !candidates.contains(candidate) else { return }
        candidates.append(candidate)
    }
}

private struct DraftShape {
    var itemKey: String
    var subjectEventID: String?
    var reason: TimelineFeedItemDraftReason
    var filterPolicy: TimelineFeedItemDraftFilterPolicy
    var futureResolveCandidates: [TimelineFeedItemDraftResolveCandidate]
}

private func sortForVisibleWindow(_ drafts: [TimelineFeedItemDraft]) -> [TimelineFeedItemDraft] {
    drafts.sorted { lhs, rhs in
        if lhs.sortAt != rhs.sortAt {
            return lhs.sortAt > rhs.sortAt
        }
        return lhs.tieBreakID < rhs.tieBreakID
    }
}

@Suite("Timeline DB bridge source model")
struct TimelineDBBridgeSourceModelTests {
    private let adapter = TimelineFeedItemDraftAdapter()

    @Test("Draft reasons stay within v0.2 feed_items reason contract")
    func draftReasonsStayWithinV02FeedItemsReasonContract() {
        let v02AllowedReasons: Set<String> = [
            "author",
            "reply",
            "repost",
            "quote",
            "mention",
            "reaction",
            "zap",
            "follow",
            "manual"
        ]
        let draftReasonRawValues = Set(TimelineFeedItemDraftReason.allCases.map(\.rawValue))
        let unsupportedID = "unsupported-reason-kind"
        let output = adapter.map(
            entries: [legacyEntry(eventID: unsupportedID)],
            events: [
                unsupportedID: legacyEvent(eventID: unsupportedID, kind: 30_023)
            ]
        )

        #expect(draftReasonRawValues.isSubset(of: v02AllowedReasons))
        #expect(!draftReasonRawValues.contains("unknown"))
        #expect(output.drafts.isEmpty)
        #expect(output.drafts.allSatisfy { v02AllowedReasons.contains($0.reason.rawValue) })
        #expect(output.issues == [
            TimelineFeedItemDraftIssue(
                kind: .unsupportedSourceKind,
                eventID: unsupportedID,
                eventKind: 30_023
            )
        ])
        #expect(output.diagnostics.unsupportedKindCount == 1)
    }

    @Test("Unsupported source event kind returns typed issue and no draft row")
    func unsupportedSourceEventKindReturnsTypedIssueAndNoDraftRow() {
        let unsupportedID = "unsupported-kind-001"
        let output = adapter.map(
            entries: [legacyEntry(eventID: unsupportedID, pendingNew: true)],
            events: [
                unsupportedID: legacyEvent(eventID: unsupportedID, kind: 30_023)
            ]
        )

        #expect(output.drafts.isEmpty)
        #expect(output.issues == [
            TimelineFeedItemDraftIssue(
                kind: .unsupportedSourceKind,
                eventID: unsupportedID,
                eventKind: 30_023
            )
        ])
        #expect(output.diagnostics.inputCount == 1)
        #expect(output.diagnostics.outputCount == 0)
        #expect(output.diagnostics.droppedCount == 1)
        #expect(output.diagnostics.unsupportedKindCount == 1)
        #expect(output.diagnostics.pendingNewCount == 0)
        #expect(output.diagnostics.unresolvedTargetCount == 0)
        #expect(!output.diagnostics.readMarkerChanged)
        #expect(!output.diagnostics.requiresNetworkWork)
        #expect(!output.diagnostics.requiresDBWork)
        #expect(TimelineFeedItemDraftAdapter.visibleWindowDrafts(output.drafts).isEmpty)
    }

    @Test("Note timeline entry maps to v0.2-like feed item draft")
    func noteTimelineEntryMapsToFeedItemDraft() throws {
        let noteID = "note-001"
        let output = adapter.map(
            entries: [
                legacyEntry(eventID: noteID, sortTimestamp: 1_700_000_100, insertedAt: 1_700_000_200)
            ],
            events: [
                noteID: legacyEvent(eventID: noteID, pubkey: "author-pubkey", kind: 1)
            ]
        )

        let draft = try #require(output.drafts.first)

        #expect(output.issues.isEmpty)
        #expect(output.diagnostics.inputCount == 1)
        #expect(output.diagnostics.outputCount == 1)
        #expect(output.diagnostics.droppedCount == 0)
        #expect(output.diagnostics.unsupportedKindCount == 0)
        #expect(draft.accountID == "account")
        #expect(draft.timelineKey == "home")
        #expect(draft.feedID == nil)
        #expect(draft.itemKey == "note:\(noteID)")
        #expect(draft.sourceEventID == noteID)
        #expect(draft.subjectEventID == noteID)
        #expect(draft.reason == .author)
        #expect(draft.actorPubkey == "author-pubkey")
        #expect(draft.sortAt == 1_700_000_100)
        #expect(draft.tieBreakID == noteID)
        #expect(draft.hiddenReason == nil)
        #expect(!draft.collapsed)
        #expect(!draft.pendingNew)
        #expect(draft.insertedAt == 1_700_000_200)
        #expect(!output.diagnostics.readMarkerChanged)
        #expect(!output.diagnostics.requiresNetworkWork)
        #expect(!output.diagnostics.requiresDBWork)
    }

    @Test("Repost maps to stable repost item key and preserves target when available")
    func repostMapsToStableItemKeyAndSubjectTarget() throws {
        let repostID = "repost-001"
        let targetID = "note-target-001"
        let output = adapter.map(
            entries: [legacyEntry(eventID: repostID)],
            events: [
                repostID: legacyEvent(eventID: repostID, kind: 6, tags: [["e", targetID]]),
                targetID: legacyEvent(eventID: targetID, kind: 1)
            ]
        )

        let draft = try #require(output.drafts.first)

        #expect(draft.itemKey == "repost:\(repostID)")
        #expect(draft.sourceEventID == repostID)
        #expect(draft.subjectEventID == targetID)
        #expect(draft.reason == .repost)
        #expect(output.diagnostics.unresolvedTargetCount == 0)
    }

    @Test("Repost with missing target remains visible and fallback capable")
    func repostMissingTargetRemainsVisibleAndFallbackCapable() throws {
        let repostID = "repost-missing-target"
        let targetID = "missing-note-target"
        let output = adapter.map(
            entries: [legacyEntry(eventID: repostID)],
            events: [
                repostID: legacyEvent(eventID: repostID, kind: 6, tags: [["e", targetID]])
            ]
        )

        let draft = try #require(output.drafts.first)

        #expect(draft.subjectEventID == targetID)
        #expect(draft.visibility == .visible)
        #expect(draft.futureResolveCandidates == [
            TimelineFeedItemDraftResolveCandidate(kind: .repostTarget, targetKey: targetID)
        ])
        #expect(TimelineFeedItemDraftAdapter.visibleWindowDrafts(output.drafts).map(\.itemKey) == [draft.itemKey])
        #expect(output.diagnostics.unresolvedTargetCount == 1)
        #expect(output.diagnostics.droppedCount == 0)
    }

    @Test("Pending new defaults false and explicit pending new waits for user action")
    func pendingNewDefaultsFalseAndWaitsForUserAction() throws {
        let visibleID = "note-visible"
        let pendingID = "note-pending"
        let output = adapter.map(
            entries: [
                legacyEntry(eventID: visibleID),
                legacyEntry(eventID: pendingID, sortTimestamp: 9, pendingNew: true)
            ],
            events: [
                visibleID: legacyEvent(eventID: visibleID),
                pendingID: legacyEvent(eventID: pendingID)
            ]
        )

        let visibleWindow = TimelineFeedItemDraftAdapter.visibleWindowDrafts(output.drafts)
        let explicitWindow = TimelineFeedItemDraftAdapter.visibleWindowDrafts(
            output.drafts,
            explicitPendingNewItemKeys: ["note:\(pendingID)"]
        )

        #expect(output.drafts.first(where: { $0.sourceEventID == visibleID })?.pendingNew == false)
        #expect(output.drafts.first(where: { $0.sourceEventID == pendingID })?.pendingNew == true)
        #expect(visibleWindow.map(\.sourceEventID) == [visibleID])
        #expect(explicitWindow.map(\.sourceEventID) == [visibleID, pendingID])
        #expect(output.diagnostics.pendingNewCount == 1)
        #expect(!output.diagnostics.readMarkerChanged)
    }

    @Test("Hidden collapsed defaults and muted collapsed draft remains represented")
    func hiddenCollapsedDefaultsAndMutedCollapsedDraftRemainsRepresented() throws {
        let normalID = "note-normal"
        let hiddenID = "note-hidden"
        let mutedID = "note-muted"
        let output = adapter.map(
            entries: [
                legacyEntry(eventID: normalID, sortTimestamp: 30),
                legacyEntry(eventID: hiddenID, sortTimestamp: 20, visibility: .hidden(reason: "deleted")),
                legacyEntry(eventID: mutedID, sortTimestamp: 10, visibility: .mutedCollapsed)
            ],
            events: [
                normalID: legacyEvent(eventID: normalID),
                hiddenID: legacyEvent(eventID: hiddenID),
                mutedID: legacyEvent(eventID: mutedID)
            ]
        )

        let normal = try #require(output.drafts.first(where: { $0.sourceEventID == normalID }))
        let hidden = try #require(output.drafts.first(where: { $0.sourceEventID == hiddenID }))
        let muted = try #require(output.drafts.first(where: { $0.sourceEventID == mutedID }))

        #expect(normal.hiddenReason == nil)
        #expect(!normal.collapsed)
        #expect(hidden.hiddenReason == "deleted")
        #expect(!hidden.collapsed)
        #expect(muted.hiddenReason == nil)
        #expect(muted.collapsed)
        #expect(TimelineFeedItemDraftAdapter.visibleWindowDrafts(output.drafts).map(\.sourceEventID) == [
            normalID,
            mutedID
        ])
    }

    @Test("Reply policy keeps source data and defers include replies filtering")
    func replyPolicyKeepsSourceDataAndDefersFiltering() throws {
        let replyID = "reply-001"
        let parentID = "parent-001"
        let output = adapter.map(
            entries: [legacyEntry(eventID: replyID)],
            events: [
                replyID: legacyEvent(eventID: replyID, kind: 1, tags: [["e", parentID, "", "reply"]])
            ]
        )

        let draft = try #require(output.drafts.first)

        #expect(draft.reason == .reply)
        #expect(draft.subjectEventID == replyID)
        #expect(draft.filterPolicy == .deferToFutureMaterializer)
        #expect(draft.futureResolveCandidates == [
            TimelineFeedItemDraftResolveCandidate(kind: .replyParentRoot, targetKey: parentID)
        ])
    }

    @Test("Unresolved enrichment targets remain future resolve candidates only")
    func unresolvedEnrichmentTargetsRemainFutureResolveCandidatesOnly() throws {
        let noteID = "note-with-unresolved-hints"
        let quoteID = "quote-target-001"
        let replyID = "reply-parent-001"
        let output = adapter.map(
            entries: [legacyEntry(eventID: noteID)],
            events: [
                noteID: legacyEvent(
                    eventID: noteID,
                    kind: 1,
                    tags: [
                        ["p", "profile-pubkey"],
                        ["r", "https://example.invalid/article"],
                        ["imeta", "url https://example.invalid/image.png"],
                        ["q", quoteID],
                        ["e", replyID, "", "reply"]
                    ]
                )
            ]
        )

        let draft = try #require(output.drafts.first)
        let candidateKinds = Set(draft.futureResolveCandidates.map(\.kind))

        #expect(candidateKinds == [
            .profile,
            .linkPreviewOGP,
            .media,
            .quoteTarget,
            .replyParentRoot
        ])
        #expect(output.diagnostics.unresolvedTargetCount == draft.futureResolveCandidates.count)
        #expect(!output.diagnostics.requiresNetworkWork)
        #expect(!output.diagnostics.requiresDBWork)
    }

    @Test("Adapter produces deterministic ordering and deduplicates item keys")
    func adapterProducesDeterministicOrderingAndDeduplicatesItemKeys() {
        let olderA = "note-a"
        let olderB = "note-b"
        let newer = "note-newer"
        let output = adapter.map(
            entries: [
                legacyEntry(eventID: olderB, sortTimestamp: 10),
                legacyEntry(eventID: newer, sortTimestamp: 20),
                legacyEntry(eventID: olderA, sortTimestamp: 10),
                legacyEntry(eventID: newer, sortTimestamp: 15)
            ],
            events: [
                olderA: legacyEvent(eventID: olderA),
                olderB: legacyEvent(eventID: olderB),
                newer: legacyEvent(eventID: newer)
            ]
        )

        #expect(output.drafts.map(\.sourceEventID) == [newer, olderA, olderB])
        #expect(Set(output.drafts.map(\.itemKey)).count == output.drafts.count)
        #expect(output.issues.contains { $0.kind == .duplicateItemKey && $0.eventID == newer })
    }

    @Test("Invalid missing event ID returns typed issue")
    func invalidMissingEventIDReturnsTypedIssue() {
        let output = adapter.map(
            entries: [
                TimelineLegacyEntryRecordDraft(
                    accountID: "account",
                    timelineKey: "home",
                    eventID: nil,
                    sortTimestamp: 10,
                    source: "home",
                    insertedAt: 20
                )
            ],
            events: [:]
        )

        #expect(output.drafts.isEmpty)
        #expect(output.issues == [
            TimelineFeedItemDraftIssue(kind: .missingEventID, eventID: nil)
        ])
        #expect(output.diagnostics.droppedCount == 1)
    }

    @Test("Source model types are codable equatable and sendable")
    func sourceModelTypesAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineLegacyEntryRecordDraft.self)
        assertSendable(TimelineLegacyEventRecordDraft.self)
        assertSendable(TimelineFeedItemDraft.self)
        assertSendable(TimelineFeedItemDraftReason.self)
        assertSendable(TimelineFeedItemDraftVisibility.self)
        assertSendable(TimelineFeedItemDraftIssue.self)
        assertSendable(TimelineFeedItemDraftDiagnostics.self)

        let output = adapter.map(
            entries: [legacyEntry(eventID: "note-codable")],
            events: ["note-codable": legacyEvent(eventID: "note-codable")]
        )

        try assertCodableRoundTrip(try #require(output.drafts.first))
        try assertCodableRoundTrip(output.issues)
        try assertCodableRoundTrip(output.diagnostics)
    }

    private func legacyEntry(
        eventID: String,
        sortTimestamp: Int64 = 10,
        source: String = "home",
        insertedAt: Int64 = 20,
        pendingNew: Bool = false,
        visibility: TimelineFeedItemDraftVisibility = .visible
    ) -> TimelineLegacyEntryRecordDraft {
        TimelineLegacyEntryRecordDraft(
            accountID: "account",
            timelineKey: "home",
            eventID: eventID,
            sortTimestamp: sortTimestamp,
            source: source,
            insertedAt: insertedAt,
            pendingNew: pendingNew,
            visibility: visibility
        )
    }

    private func legacyEvent(
        eventID: String,
        pubkey: String = "pubkey",
        kind: Int = 1,
        tags: [[String]] = []
    ) -> TimelineLegacyEventRecordDraft {
        TimelineLegacyEventRecordDraft(
            eventID: eventID,
            pubkey: pubkey,
            kind: kind,
            tags: tags
        )
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    private func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)

        #expect(decoded == value)
    }
}
