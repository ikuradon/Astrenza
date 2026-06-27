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

private struct TimelineDBBridgeRepositoryPipelineDiagnostics: Equatable, Codable, Sendable {
    var sourceInputCount: Int
    var adapterOutputCount: Int
    var repositoryVisibleOutputCount: Int
    var droppedRejectedCount: Int
    var excludedPendingNewCount: Int
    var excludedHiddenCount: Int
    var collapsedCount: Int
    var fallbackReason: TimelineRepositoryBoundaryFallbackReason
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
}

private struct TimelineDBBridgeRepositoryPipelineOutput: Equatable, Codable, Sendable {
    var adapterIssues: [TimelineFeedItemDraftIssue]
    var repositoryIssues: [TimelineRepositoryBoundaryIssue]
    var initialWindow: TimelineInitialWindowDraft
    var diagnostics: TimelineDBBridgeRepositoryPipelineDiagnostics
}

private struct TimelineDBBridgeRepositoryPipeline: Sendable {
    private let adapter = TimelineFeedItemDraftAdapter()
    private let repositoryBoundary = FixtureTimelineRepositoryBoundary()

    func initialWindow(
        entries: [TimelineLegacyEntryRecordDraft],
        events: [String: TimelineLegacyEventRecordDraft],
        feedID: FeedID = .debugHome,
        readState: TimelineReadStateDraft? = nil,
        policy: TimelineVisibleWindowPolicy = .initialRestore(maxVisibleCount: 10),
        attemptsTimelineEntriesOnlyAnchorDerivation: Bool = false,
        attemptsReadMarkerAdvance: Bool = false,
        preservesAdapterDuplicateIssuesForRepository: Bool = false,
        mutateRepositoryRows: ((inout [TimelineRepositoryFeedItemDraftRow]) -> Void)? = nil
    ) -> TimelineDBBridgeRepositoryPipelineOutput {
        let adapterOutput = adapter.map(entries: entries, events: events)
        var repositoryRows = adapterOutput.drafts.map(repositoryRow)

        if preservesAdapterDuplicateIssuesForRepository,
           let duplicate = duplicateRepositoryRow(from: adapterOutput, entries: entries, events: events) {
            repositoryRows.append(duplicate)
        }

        mutateRepositoryRows?(&repositoryRows)

        let initialWindow = repositoryBoundary.initialWindow(TimelineInitialWindowRequest(
            feedID: feedID,
            rows: repositoryRows,
            readState: readState,
            policy: policy,
            attemptsTimelineEntriesOnlyAnchorDerivation: attemptsTimelineEntriesOnlyAnchorDerivation,
            attemptsReadMarkerAdvance: attemptsReadMarkerAdvance
        ))

        return TimelineDBBridgeRepositoryPipelineOutput(
            adapterIssues: adapterOutput.issues,
            repositoryIssues: initialWindow.issues,
            initialWindow: initialWindow,
            diagnostics: pipelineDiagnostics(
                adapterOutput: adapterOutput,
                initialWindow: initialWindow
            )
        )
    }

    private func repositoryRow(
        from draft: TimelineFeedItemDraft
    ) -> TimelineRepositoryFeedItemDraftRow {
        TimelineRepositoryFeedItemDraftRow(
            itemKey: draft.itemKey,
            sourceEventID: EventID(hex: draft.sourceEventID),
            subjectEventID: draft.subjectEventID.map(EventID.init(hex:)),
            reason: TimelineRepositoryFeedItemReason(draft.reason),
            actorPubkey: draft.actorPubkey,
            sortAt: draft.sortAt,
            tieBreakID: draft.tieBreakID,
            hiddenReason: draft.hiddenReason,
            collapsed: draft.collapsed,
            pendingNew: draft.pendingNew,
            isMissingTargetFallbackCapable: draft.futureResolveCandidates.contains { candidate in
                candidate.kind == .repostTarget || candidate.kind == .quoteTarget
            }
        )
    }

    private func duplicateRepositoryRow(
        from adapterOutput: TimelineFeedItemDraftAdapterOutput,
        entries: [TimelineLegacyEntryRecordDraft],
        events: [String: TimelineLegacyEventRecordDraft]
    ) -> TimelineRepositoryFeedItemDraftRow? {
        guard let duplicateEventID = adapterOutput.issues.first(where: { issue in
            issue.kind == .duplicateItemKey
        })?.eventID,
              let duplicateEntry = entries.first(where: { $0.eventID == duplicateEventID }),
              let duplicateEvent = events[duplicateEventID] else {
            return nil
        }

        let duplicateDraft = adapter.map(
            entries: [duplicateEntry],
            events: [duplicateEventID: duplicateEvent]
        ).drafts.first
        return duplicateDraft.map(repositoryRow)
    }

    private func pipelineDiagnostics(
        adapterOutput: TimelineFeedItemDraftAdapterOutput,
        initialWindow: TimelineInitialWindowDraft
    ) -> TimelineDBBridgeRepositoryPipelineDiagnostics {
        let rejectedByRepositoryCount = initialWindow.issues.filter { issue in
            switch issue.kind {
            case .duplicateItemKey, .invalidItemKey, .invalidSortKey:
                return true
            case .missingAnchor,
                 .missingScrollAnchorEvent,
                 .missingMarker,
                 .missingLastVisible,
                 .pendingNewIncludedWithoutExplicitUserAction,
                 .hiddenRowIncludedByMistake,
                 .timelineEntriesOnlyAnchorDerivationAttempted,
                 .readMarkerAdvanceAttempted:
                return false
            }
        }.count

        return TimelineDBBridgeRepositoryPipelineDiagnostics(
            sourceInputCount: adapterOutput.diagnostics.inputCount,
            adapterOutputCount: adapterOutput.diagnostics.outputCount,
            repositoryVisibleOutputCount: initialWindow.diagnostics.visibleOutputCount,
            droppedRejectedCount: adapterOutput.diagnostics.droppedCount + rejectedByRepositoryCount,
            excludedPendingNewCount: initialWindow.diagnostics.excludedPendingNewCount,
            excludedHiddenCount: initialWindow.diagnostics.excludedHiddenCount,
            collapsedCount: initialWindow.diagnostics.collapsedCount,
            fallbackReason: initialWindow.diagnostics.fallbackReason,
            readMarkerChanged: adapterOutput.diagnostics.readMarkerChanged
                || initialWindow.diagnostics.readMarkerChanged,
            requiresNetworkWork: adapterOutput.diagnostics.requiresNetworkWork
                || initialWindow.diagnostics.requiresNetworkWork,
            requiresDBWork: adapterOutput.diagnostics.requiresDBWork
                || initialWindow.diagnostics.requiresDBWork
        )
    }
}

private extension TimelineRepositoryFeedItemReason {
    init(_ draftReason: TimelineFeedItemDraftReason) {
        switch draftReason {
        case .author:
            self = .author
        case .reply:
            self = .reply
        case .repost:
            self = .repost
        case .quote:
            self = .quote
        case .mention:
            self = .mention
        case .reaction:
            self = .reaction
        case .zap:
            self = .zap
        case .follow:
            self = .follow
        case .manual:
            self = .manual
        }
    }
}

@Suite("Timeline DB bridge repository pipeline")
struct TimelineDBBridgeRepositoryPipelineTests {
    private let pipeline = TimelineDBBridgeRepositoryPipeline()

    @Test("timeline_entries-like note records map through adapter and repository into initial window")
    func noteRecordsMapThroughAdapterAndRepositoryIntoInitialWindow() {
        let output = pipeline.initialWindow(
            entries: [
                legacyEntry(eventID: "note-older", sortTimestamp: 10),
                legacyEntry(eventID: "note-newer", sortTimestamp: 20)
            ],
            events: [
                "note-older": legacyEvent(eventID: "note-older"),
                "note-newer": legacyEvent(eventID: "note-newer")
            ],
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(output.adapterIssues.isEmpty)
        #expect(output.repositoryIssues.isEmpty)
        #expect(output.initialWindow.visibleItemKeys == ["note:note-newer", "note:note-older"])
        #expect(output.diagnostics.sourceInputCount == 2)
        #expect(output.diagnostics.adapterOutputCount == 2)
        #expect(output.diagnostics.repositoryVisibleOutputCount == 2)
        #expect(output.diagnostics.droppedRejectedCount == 0)
        #expect(output.diagnostics.excludedPendingNewCount == 0)
        #expect(output.diagnostics.excludedHiddenCount == 0)
        #expect(output.diagnostics.collapsedCount == 0)
        #expect(output.diagnostics.fallbackReason == .noReadStateUsedNewest)
        #expect(!output.diagnostics.readMarkerChanged)
        #expect(!output.diagnostics.requiresNetworkWork)
        #expect(!output.diagnostics.requiresDBWork)
    }

    @Test("repost source record maps through adapter and repository with stable repost item_key")
    func repostSourceRecordMapsThroughAdapterAndRepositoryWithStableItemKey() throws {
        let output = pipeline.initialWindow(
            entries: [
                legacyEntry(eventID: "repost-001", sortTimestamp: 30),
                legacyEntry(eventID: "note-target", sortTimestamp: 20)
            ],
            events: [
                "repost-001": legacyEvent(eventID: "repost-001", kind: 6, tags: [["e", "note-target"]]),
                "note-target": legacyEvent(eventID: "note-target")
            ]
        )

        let repost = try #require(output.initialWindow.visibleRows.first)

        #expect(output.initialWindow.visibleItemKeys == ["repost:repost-001", "note:note-target"])
        #expect(repost.itemKey == "repost:repost-001")
        #expect(repost.sourceEventID == eventID("repost-001"))
        #expect(repost.subjectEventID == eventID("note-target"))
        #expect(repost.reason == .repost)
    }

    @Test("missing repost or quote target remains visible fallback capable through repository boundary")
    func missingTargetRemainsVisibleFallbackCapableThroughRepositoryBoundary() throws {
        let repostOutput = pipeline.initialWindow(
            entries: [legacyEntry(eventID: "repost-missing-target", sortTimestamp: 30)],
            events: [
                "repost-missing-target": legacyEvent(
                    eventID: "repost-missing-target",
                    kind: 6,
                    tags: [["e", "missing-target"]]
                )
            ]
        )
        let quoteOutput = pipeline.initialWindow(
            entries: [legacyEntry(eventID: "note-with-missing-quote", sortTimestamp: 20)],
            events: [
                "note-with-missing-quote": legacyEvent(
                    eventID: "note-with-missing-quote",
                    tags: [["q", "missing-quote-target"]]
                )
            ]
        )

        let repostRow = try #require(repostOutput.initialWindow.visibleRows.first)
        let quoteRow = try #require(quoteOutput.initialWindow.visibleRows.first)

        #expect(repostOutput.adapterIssues.isEmpty)
        #expect(repostOutput.repositoryIssues.isEmpty)
        #expect(repostOutput.initialWindow.visibleItemKeys == ["repost:repost-missing-target"])
        #expect(repostRow.isMissingTargetFallbackCapable)
        #expect(repostRow.subjectEventID == eventID("missing-target"))
        #expect(repostOutput.diagnostics.droppedRejectedCount == 0)
        #expect(quoteOutput.adapterIssues.isEmpty)
        #expect(quoteOutput.repositoryIssues.isEmpty)
        #expect(quoteOutput.initialWindow.visibleItemKeys == ["note:note-with-missing-quote"])
        #expect(quoteRow.isMissingTargetFallbackCapable)
        #expect(quoteRow.sourceEventID == eventID("note-with-missing-quote"))
        #expect(quoteOutput.diagnostics.droppedRejectedCount == 0)
    }

    @Test("unsupported source kind is rejected before repository window and does not produce output")
    func unsupportedSourceKindIsRejectedBeforeRepositoryWindow() {
        let output = pipeline.initialWindow(
            entries: [legacyEntry(eventID: "unsupported-001", sortTimestamp: 30)],
            events: [
                "unsupported-001": legacyEvent(eventID: "unsupported-001", kind: 30_023)
            ]
        )

        #expect(output.initialWindow.visibleRows.isEmpty)
        #expect(output.adapterIssues == [
            TimelineFeedItemDraftIssue(
                kind: .unsupportedSourceKind,
                eventID: "unsupported-001",
                eventKind: 30_023
            )
        ])
        #expect(output.repositoryIssues.isEmpty)
        #expect(output.diagnostics.sourceInputCount == 1)
        #expect(output.diagnostics.adapterOutputCount == 0)
        #expect(output.diagnostics.repositoryVisibleOutputCount == 0)
        #expect(output.diagnostics.droppedRejectedCount == 1)
        #expect(output.diagnostics.fallbackReason == .noVisibleRows)
    }

    @Test("pending_new defaults excluded and explicit user action includes pending rows through full pipeline")
    func pendingNewDefaultAndExplicitInclusionFlowThroughFullPipeline() {
        let entries = [
            legacyEntry(eventID: "note-visible", sortTimestamp: 10),
            legacyEntry(eventID: "note-pending", sortTimestamp: 20, pendingNew: true)
        ]
        let events = [
            "note-visible": legacyEvent(eventID: "note-visible"),
            "note-pending": legacyEvent(eventID: "note-pending")
        ]

        let defaultOutput = pipeline.initialWindow(
            entries: entries,
            events: events,
            policy: .initialRestore(maxVisibleCount: 10)
        )
        let explicitOutput = pipeline.initialWindow(
            entries: entries,
            events: events,
            policy: .explicitUserPendingNew(itemKeys: ["note:note-pending"], maxVisibleCount: 10)
        )

        #expect(defaultOutput.initialWindow.visibleItemKeys == ["note:note-visible"])
        #expect(defaultOutput.diagnostics.excludedPendingNewCount == 1)
        #expect(explicitOutput.initialWindow.visibleItemKeys == ["note:note-pending", "note:note-visible"])
        #expect(explicitOutput.diagnostics.excludedPendingNewCount == 0)
        #expect(explicitOutput.initialWindow.diagnostics.pendingNewIncludedCount == 1)
        #expect(explicitOutput.initialWindow.diagnostics.pendingNewInclusionReason == .explicitUserAction)
    }

    @Test("hidden rows are excluded and collapsed muted rows remain represented through full pipeline")
    func hiddenAndCollapsedBehaviorSurvivesRepositoryBoundary() throws {
        let output = pipeline.initialWindow(
            entries: [
                legacyEntry(eventID: "note-visible", sortTimestamp: 30),
                legacyEntry(eventID: "note-hidden", sortTimestamp: 20, visibility: .hidden(reason: "muted")),
                legacyEntry(eventID: "note-collapsed", sortTimestamp: 10, visibility: .mutedCollapsed)
            ],
            events: [
                "note-visible": legacyEvent(eventID: "note-visible"),
                "note-hidden": legacyEvent(eventID: "note-hidden"),
                "note-collapsed": legacyEvent(eventID: "note-collapsed")
            ]
        )

        let collapsed = try #require(output.initialWindow.visibleRows.last)

        #expect(output.initialWindow.visibleItemKeys == ["note:note-visible", "note:note-collapsed"])
        #expect(collapsed.itemKey == "note:note-collapsed")
        #expect(collapsed.collapsed)
        #expect(output.diagnostics.excludedHiddenCount == 1)
        #expect(output.diagnostics.collapsedCount == 1)
    }

    @Test("read-state anchor marker and newest fallbacks stay distinct through full pipeline")
    func readStateAnchorMarkerAndNewestFallbacksStayDistinctThroughFullPipeline() {
        let entries = [
            legacyEntry(eventID: "note-a", sortTimestamp: 10),
            legacyEntry(eventID: "note-b", sortTimestamp: 20),
            legacyEntry(eventID: "note-c", sortTimestamp: 30),
            legacyEntry(eventID: "note-d", sortTimestamp: 40),
            legacyEntry(eventID: "note-e", sortTimestamp: 50)
        ]
        let events = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            entry.eventID.map { ($0, legacyEvent(eventID: $0)) }
        })

        let anchorPresent = pipeline.initialWindow(
            entries: entries,
            events: events,
            readState: TimelineReadStateDraft(
                scrollAnchorItemKey: "note:note-c",
                scrollAnchorSortAt: 30,
                scrollAnchorTieBreakID: "note-c",
                markerItemKey: "note:note-e",
                markerEventID: eventID("note-e"),
                markerSortAt: 50
            ),
            policy: .initialRestore(maxVisibleCount: 3)
        )
        let missingAnchor = pipeline.initialWindow(
            entries: entries,
            events: events,
            readState: TimelineReadStateDraft(
                scrollAnchorItemKey: "note:missing",
                markerItemKey: "note:note-b",
                markerEventID: eventID("note-b"),
                markerSortAt: 20
            ),
            policy: .initialRestore(maxVisibleCount: 3)
        )
        let newestFallback = pipeline.initialWindow(
            entries: entries,
            events: events,
            policy: .initialRestore(maxVisibleCount: 3)
        )
        let missingMarker = pipeline.initialWindow(
            entries: entries,
            events: events,
            readState: TimelineReadStateDraft(
                markerItemKey: "note:missing-marker",
                markerEventID: eventID("missing-marker")
            ),
            policy: .initialRestore(maxVisibleCount: 3)
        )

        #expect(anchorPresent.initialWindow.anchorItemKey == "note:note-c")
        #expect(anchorPresent.initialWindow.anchorSource == .scrollAnchor)
        #expect(anchorPresent.initialWindow.visibleItemKeys == ["note:note-d", "note:note-c", "note:note-b"])
        #expect(anchorPresent.diagnostics.fallbackReason == .anchorFound)
        #expect(missingAnchor.initialWindow.anchorItemKey == "note:note-b")
        #expect(missingAnchor.initialWindow.anchorSource == .readMarker)
        #expect(missingAnchor.diagnostics.fallbackReason == .missingAnchorUsedMarker)
        #expect(missingAnchor.repositoryIssues.contains { $0.kind == .missingAnchor })
        #expect(newestFallback.initialWindow.anchorItemKey == "note:note-e")
        #expect(newestFallback.initialWindow.anchorSource == .newest)
        #expect(newestFallback.diagnostics.fallbackReason == .noReadStateUsedNewest)
        #expect(missingMarker.initialWindow.anchorItemKey == "note:note-e")
        #expect(missingMarker.initialWindow.anchorSource == .newest)
        #expect(missingMarker.diagnostics.fallbackReason == .missingMarkerUsedNewest)
        #expect(missingMarker.repositoryIssues.contains { issue in
            issue.kind == .missingMarker
                && issue.itemKey == "note:missing-marker"
                && issue.eventID == eventID("missing-marker")
        })
        #expect(!anchorPresent.diagnostics.readMarkerChanged)
        #expect(!missingAnchor.diagnostics.readMarkerChanged)
        #expect(!newestFallback.diagnostics.readMarkerChanged)
        #expect(!missingMarker.diagnostics.readMarkerChanged)
    }

    @Test("repository boundary does not derive anchor from timeline_entries alone")
    func repositoryBoundaryDoesNotDeriveAnchorFromTimelineEntriesAlone() {
        let output = pipeline.initialWindow(
            entries: [
                legacyEntry(eventID: "note-anchorish", sortTimestamp: 30),
                legacyEntry(eventID: "note-newest", sortTimestamp: 40)
            ],
            events: [
                "note-anchorish": legacyEvent(eventID: "note-anchorish"),
                "note-newest": legacyEvent(eventID: "note-newest")
            ],
            attemptsTimelineEntriesOnlyAnchorDerivation: true
        )

        #expect(output.initialWindow.anchorItemKey == "note:note-newest")
        #expect(output.initialWindow.anchorSource == .newest)
        #expect(output.repositoryIssues.contains { $0.kind == .timelineEntriesOnlyAnchorDerivationAttempted })
        #expect(!output.diagnostics.readMarkerChanged)
    }

    @Test("duplicate and invalid repository issues remain typed and distinguishable from adapter issues")
    func duplicateAndInvalidRepositoryIssuesRemainTypedAndDistinguishable() {
        let duplicate = pipeline.initialWindow(
            entries: [
                legacyEntry(eventID: "note-dup", sortTimestamp: 30),
                legacyEntry(eventID: "note-dup", sortTimestamp: 10),
                legacyEntry(eventID: "unsupported-001", sortTimestamp: 20)
            ],
            events: [
                "note-dup": legacyEvent(eventID: "note-dup"),
                "unsupported-001": legacyEvent(eventID: "unsupported-001", kind: 30_023)
            ],
            preservesAdapterDuplicateIssuesForRepository: true
        )
        let invalidItemKey = pipeline.initialWindow(
            entries: [legacyEntry(eventID: "note-invalid-item", sortTimestamp: 30)],
            events: ["note-invalid-item": legacyEvent(eventID: "note-invalid-item")],
            mutateRepositoryRows: { rows in
                rows[0].itemKey = "   "
            }
        )
        let invalidSortKey = pipeline.initialWindow(
            entries: [legacyEntry(eventID: "note-invalid-sort", sortTimestamp: 30)],
            events: ["note-invalid-sort": legacyEvent(eventID: "note-invalid-sort")],
            mutateRepositoryRows: { rows in
                rows[0].sortAt = nil
            }
        )

        #expect(duplicate.adapterIssues.contains { $0.kind == .unsupportedSourceKind })
        #expect(duplicate.repositoryIssues.contains { $0.kind == .duplicateItemKey })
        #expect(invalidItemKey.adapterIssues.isEmpty)
        #expect(invalidItemKey.repositoryIssues.contains { $0.kind == .invalidItemKey })
        #expect(invalidSortKey.adapterIssues.isEmpty)
        #expect(invalidSortKey.repositoryIssues.contains { $0.kind == .invalidSortKey })
    }

    @Test("pipeline models are Codable Equatable and Sendable where appropriate")
    func pipelineModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineDBBridgeRepositoryPipeline.self)
        assertSendable(TimelineDBBridgeRepositoryPipelineOutput.self)
        assertSendable(TimelineDBBridgeRepositoryPipelineDiagnostics.self)

        let output = pipeline.initialWindow(
            entries: [legacyEntry(eventID: "note-codable")],
            events: ["note-codable": legacyEvent(eventID: "note-codable")]
        )

        try assertCodableRoundTrip(output.diagnostics)
        try assertCodableRoundTrip(output)
    }

    private func legacyEntry(
        eventID: String,
        sortTimestamp: Int64 = 10,
        insertedAt: Int64 = 20,
        pendingNew: Bool = false,
        visibility: TimelineFeedItemDraftVisibility = .visible
    ) -> TimelineLegacyEntryRecordDraft {
        TimelineLegacyEntryRecordDraft(
            accountID: "account",
            timelineKey: "home",
            eventID: eventID,
            sortTimestamp: sortTimestamp,
            source: "home",
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

    private func eventID(_ value: String) -> EventID {
        EventID(hex: value)
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    private func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)

        #expect(decoded == value)
    }
}

@Suite("TimelineRepositoryBoundary source-model contract")
struct TimelineRepositoryBoundaryContractTests {
    private let boundary = FixtureTimelineRepositoryBoundary()

    @Test("Initial window orders feed item drafts deterministically")
    func initialWindowOrdersFeedItemDraftsDeterministically() {
        let draft = boundary.initialWindow(request(rows: [
            row("note:older-b", sortAt: 10, tieBreakID: "b"),
            row("note:newest", sortAt: 20, tieBreakID: "z"),
            row("note:older-a", sortAt: 10, tieBreakID: "a")
        ], policy: .initialRestore(maxVisibleCount: 10)))

        #expect(draft.issues.isEmpty)
        #expect(draft.visibleItemKeys == ["note:newest", "note:older-a", "note:older-b"])
        #expect(draft.diagnostics.inputCount == 3)
        #expect(draft.diagnostics.visibleOutputCount == 3)
        #expect(draft.diagnostics.fallbackReason == .noReadStateUsedNewest)
    }

    @Test("Pending new rows are excluded by default")
    func pendingNewRowsAreExcludedByDefault() {
        let draft = boundary.initialWindow(request(rows: [
            row("note:visible", sortAt: 10),
            row("note:pending", sortAt: 20, pendingNew: true)
        ], policy: .initialRestore(maxVisibleCount: 10)))

        #expect(draft.visibleItemKeys == ["note:visible"])
        #expect(draft.diagnostics.excludedPendingNewCount == 1)
        #expect(draft.diagnostics.pendingNewIncludedCount == 0)
        #expect(draft.diagnostics.pendingNewInclusionReason == nil)
    }

    @Test("Explicit pending new user action includes pending rows")
    func explicitPendingNewUserActionIncludesPendingRows() {
        let draft = boundary.initialWindow(request(rows: [
            row("note:visible", sortAt: 10),
            row("note:pending", sortAt: 20, pendingNew: true)
        ], policy: .explicitUserPendingNew(itemKeys: ["note:pending"], maxVisibleCount: 10)))

        #expect(draft.issues.isEmpty)
        #expect(draft.visibleItemKeys == ["note:pending", "note:visible"])
        #expect(draft.diagnostics.excludedPendingNewCount == 0)
        #expect(draft.diagnostics.pendingNewIncludedCount == 1)
        #expect(draft.diagnostics.pendingNewInclusionReason == .explicitUserAction)
    }

    @Test("Hidden rows are excluded")
    func hiddenRowsAreExcluded() {
        let draft = boundary.initialWindow(request(rows: [
            row("note:visible", sortAt: 10),
            row("note:hidden", sortAt: 20, hiddenReason: "deleted")
        ], policy: .initialRestore(maxVisibleCount: 10)))

        #expect(draft.visibleItemKeys == ["note:visible"])
        #expect(draft.diagnostics.excludedHiddenCount == 1)
    }

    @Test("Collapsed rows remain represented")
    func collapsedRowsRemainRepresented() {
        let draft = boundary.initialWindow(request(rows: [
            row("note:collapsed", sortAt: 20, collapsed: true),
            row("note:visible", sortAt: 10)
        ], policy: .initialRestore(maxVisibleCount: 10)))

        #expect(draft.visibleItemKeys == ["note:collapsed", "note:visible"])
        #expect(draft.visibleRows.first?.collapsed == true)
        #expect(draft.diagnostics.collapsedCount == 1)
    }

    @Test("Missing repost or quote target fallback capable row remains visible")
    func missingTargetFallbackCapableRowRemainsVisible() {
        let draft = boundary.initialWindow(request(rows: [
            row(
                "repost:source-001",
                sourceEventID: "source-001",
                subjectEventID: nil,
                reason: .repost,
                isMissingTargetFallbackCapable: true
            )
        ]))

        #expect(draft.visibleItemKeys == ["repost:source-001"])
        #expect(draft.visibleRows.first?.isMissingTargetFallbackCapable == true)
    }

    @Test("Anchor item found creates anchor-centered window")
    func anchorItemFoundCreatesAnchorCenteredWindow() {
        let draft = boundary.initialWindow(request(
            rows: fiveRows(),
            readState: TimelineReadStateDraft(
                accountID: AccountID(rawValue: "account-a"),
                feedID: .debugHome,
                timelineKey: TimelineKey(rawValue: "home"),
                scrollAnchorItemKey: "note:c",
                scrollAnchorEventID: eventID("event-c"),
                scrollAnchorSortAt: 30,
                scrollAnchorTieBreakID: "c",
                scrollAnchorOffsetPX: 12,
                viewportHeightPX: 844,
                viewportWidthPX: 390,
                contentInsetTopPX: 8,
                contentInsetBottomPX: 16,
                markerItemKey: "note:e",
                markerEventID: eventID("event-e"),
                markerSortAt: 50,
                lastVisibleTopItemKey: "note:d",
                lastVisibleBottomItemKey: "note:b",
                restoreFallbackReason: .anchorFound,
                savedAtMS: 1_780_000_000_000,
                schemaVersion: 2
            ),
            policy: .initialRestore(maxVisibleCount: 3)
        ))

        #expect(draft.issues.isEmpty)
        #expect(draft.anchorItemKey == "note:c")
        #expect(draft.anchorSource == .scrollAnchor)
        #expect(draft.visibleItemKeys == ["note:d", "note:c", "note:b"])
        #expect(draft.diagnostics.fallbackReason == .anchorFound)
        #expect(draft.diagnostics.fallbackItemKey == "note:c")
        #expect(draft.diagnostics.requestedAnchorItemKey == "note:c")
        #expect(draft.diagnostics.requestedAnchorEventID == eventID("event-c"))
        #expect(draft.diagnostics.requestedMarkerEventID == eventID("event-e"))
        #expect(draft.diagnostics.requestedLastVisibleTopItemKey == "note:d")
        #expect(draft.diagnostics.requestedLastVisibleBottomItemKey == "note:b")
        #expect(!draft.diagnostics.readMarkerChanged)
    }

    @Test("Scroll anchor event fallback works when anchor item key is missing")
    func scrollAnchorEventFallbackWorksWhenAnchorItemKeyMissing() {
        let draft = boundary.initialWindow(request(
            rows: fiveRows(),
            readState: TimelineReadStateDraft(
                scrollAnchorItemKey: "note:missing",
                scrollAnchorEventID: eventID("event-c"),
                markerEventID: eventID("event-b")
            ),
            policy: .initialRestore(maxVisibleCount: 3)
        ))

        #expect(draft.anchorItemKey == "note:c")
        #expect(draft.anchorSource == .scrollAnchor)
        #expect(draft.visibleItemKeys == ["note:d", "note:c", "note:b"])
        #expect(draft.diagnostics.fallbackReason == .missingAnchorUsedScrollEvent)
        #expect(draft.diagnostics.fallbackItemKey == "note:c")
        #expect(draft.issues.contains { $0.kind == .missingAnchor && $0.itemKey == "note:missing" })
        #expect(!draft.issues.contains { $0.kind == .missingMarker })
        #expect(!draft.diagnostics.readMarkerChanged)
    }

    @Test("Missing anchor falls back with typed fallback reason")
    func missingAnchorFallsBackWithTypedFallbackReason() {
        let draft = boundary.initialWindow(request(
            rows: [
                row("note:newest", sortAt: 20),
                row("note:older", sortAt: 10)
            ],
            readState: TimelineReadStateDraft(scrollAnchorItemKey: "note:missing")
        ))

        #expect(draft.visibleItemKeys == ["note:newest", "note:older"])
        #expect(draft.anchorItemKey == "note:newest")
        #expect(draft.anchorSource == .newest)
        #expect(draft.diagnostics.fallbackReason == .missingAnchorUsedNewest)
        #expect(draft.issues.contains { $0.kind == .missingAnchor && $0.itemKey == "note:missing" })
    }

    @Test("Marker event fallback is distinct from scroll anchor")
    func markerEventFallbackIsDistinctFromScrollAnchor() {
        let draft = boundary.initialWindow(request(
            rows: fiveRows(),
            readState: TimelineReadStateDraft(
                scrollAnchorItemKey: "note:missing",
                markerEventID: eventID("event-b"),
                markerSortAt: 20
            ),
            policy: .initialRestore(maxVisibleCount: 3)
        ))

        #expect(draft.anchorItemKey == "note:b")
        #expect(draft.anchorSource == .readMarker)
        #expect(draft.visibleItemKeys == ["note:c", "note:b", "note:a"])
        #expect(draft.diagnostics.fallbackReason == .missingAnchorUsedMarker)
        #expect(draft.diagnostics.fallbackItemKey == "note:b")
        #expect(draft.diagnostics.readMarkerChanged == false)
        #expect(draft.issues.contains { $0.kind == .missingAnchor })
    }

    @Test("Marker sort fallback uses represented nearest row")
    func markerSortFallbackUsesRepresentedNearestRow() {
        let draft = boundary.initialWindow(request(
            rows: fiveRows(),
            readState: TimelineReadStateDraft(
                markerEventID: eventID("event-missing-marker"),
                markerSortAt: 25
            ),
            policy: .initialRestore(maxVisibleCount: 3)
        ))

        #expect(draft.anchorItemKey == "note:c")
        #expect(draft.anchorSource == .readMarker)
        #expect(draft.visibleItemKeys == ["note:d", "note:c", "note:b"])
        #expect(draft.diagnostics.fallbackReason == .markerSortFound)
        #expect(draft.diagnostics.fallbackItemKey == "note:c")
        #expect(draft.issues.contains { issue in
            issue.kind == .missingMarker
                && issue.eventID == eventID("event-missing-marker")
        })
    }

    @Test("Last visible fallback works after anchor and marker targets are unavailable")
    func lastVisibleFallbackWorksAfterAnchorAndMarkerTargetsAreUnavailable() {
        let draft = boundary.initialWindow(request(
            rows: fiveRows(),
            readState: TimelineReadStateDraft(
                scrollAnchorItemKey: "note:missing-anchor",
                scrollAnchorEventID: eventID("event-missing-anchor"),
                markerEventID: eventID("event-missing-marker"),
                lastVisibleTopItemKey: "note:d",
                lastVisibleBottomItemKey: "note:b"
            ),
            policy: .initialRestore(maxVisibleCount: 3)
        ))

        #expect(draft.anchorItemKey == "note:d")
        #expect(draft.anchorSource == .lastVisible)
        #expect(draft.visibleItemKeys == ["note:e", "note:d", "note:c"])
        #expect(draft.diagnostics.fallbackReason == .missingAnchorAndMarkerUsedLastVisibleTop)
        #expect(draft.diagnostics.fallbackItemKey == "note:d")
        #expect(draft.issues.contains { $0.kind == .missingAnchor })
        #expect(draft.issues.contains { $0.kind == .missingScrollAnchorEvent })
        #expect(draft.issues.contains { $0.kind == .missingMarker })
        #expect(!draft.diagnostics.readMarkerChanged)
    }

    @Test("Missing marker returns typed issue and newest fallback")
    func missingMarkerReturnsTypedIssueAndNewestFallback() {
        let draft = boundary.initialWindow(request(
            rows: [
                row("note:newest", sortAt: 20),
                row("note:older", sortAt: 10)
            ],
            readState: TimelineReadStateDraft(
                markerItemKey: "note:missing",
                markerEventID: eventID("event-missing")
            )
        ))

        #expect(draft.anchorItemKey == "note:newest")
        #expect(draft.anchorSource == .newest)
        #expect(draft.diagnostics.fallbackReason == .missingMarkerUsedNewest)
        #expect(draft.diagnostics.fallbackItemKey == "note:newest")
        #expect(draft.issues.contains { issue in
            issue.kind == .missingMarker
                && issue.itemKey == "note:missing"
                && issue.eventID == eventID("event-missing")
        })
    }

    @Test("Newest fallback is used when no anchor or marker exists")
    func newestFallbackIsUsedWhenNoAnchorOrMarkerExists() {
        let draft = boundary.initialWindow(request(rows: [
            row("note:newest", sortAt: 20),
            row("note:older", sortAt: 10)
        ]))

        #expect(draft.anchorItemKey == "note:newest")
        #expect(draft.anchorSource == .newest)
        #expect(draft.diagnostics.fallbackReason == .noReadStateUsedNewest)
        #expect(draft.diagnostics.fallbackItemKey == "note:newest")
    }

    @Test("Initial window never requires network DB work or read marker mutation")
    func initialWindowNeverRequiresNetworkDBWorkOrReadMarkerMutation() {
        let draft = boundary.initialWindow(request(rows: [
            row("note:visible")
        ]))

        #expect(!draft.diagnostics.readMarkerChanged)
        #expect(!draft.diagnostics.requiresNetworkWork)
        #expect(!draft.diagnostics.requiresDBWork)
    }

    @Test("Read marker changed stays false for every fallback path")
    func readMarkerChangedStaysFalseForEveryFallbackPath() {
        let rows = fiveRows()
        let drafts = [
            boundary.initialWindow(request(
                rows: rows,
                readState: TimelineReadStateDraft(scrollAnchorItemKey: "note:c"),
                policy: .initialRestore(maxVisibleCount: 3)
            )),
            boundary.initialWindow(request(
                rows: rows,
                readState: TimelineReadStateDraft(
                    scrollAnchorItemKey: "note:missing",
                    scrollAnchorEventID: eventID("event-c")
                ),
                policy: .initialRestore(maxVisibleCount: 3)
            )),
            boundary.initialWindow(request(
                rows: rows,
                readState: TimelineReadStateDraft(markerEventID: eventID("event-b")),
                policy: .initialRestore(maxVisibleCount: 3)
            )),
            boundary.initialWindow(request(
                rows: rows,
                readState: TimelineReadStateDraft(markerSortAt: 25),
                policy: .initialRestore(maxVisibleCount: 3)
            )),
            boundary.initialWindow(request(
                rows: rows,
                readState: TimelineReadStateDraft(lastVisibleTopItemKey: "note:d"),
                policy: .initialRestore(maxVisibleCount: 3)
            )),
            boundary.initialWindow(request(rows: rows, policy: .initialRestore(maxVisibleCount: 3))),
            boundary.initialWindow(request(rows: []))
        ]

        #expect(Set(drafts.map(\.diagnostics.fallbackReason)) == Set<TimelineRepositoryBoundaryFallbackReason>([
            .anchorFound,
            .missingAnchorUsedScrollEvent,
            .markerEventFound,
            .markerSortFound,
            .lastVisibleTopFound,
            .noReadStateUsedNewest,
            .noVisibleRows
        ]))
        for draft in drafts {
            #expect(!draft.diagnostics.readMarkerChanged)
            #expect(!draft.diagnostics.requiresNetworkWork)
            #expect(!draft.diagnostics.requiresDBWork)
        }
    }

    @Test("Pending hidden collapsed and fallback-capable anchors follow visible query policy")
    func pendingHiddenCollapsedAndFallbackCapableAnchorsFollowVisibleQueryPolicy() {
        let defaultPending = boundary.initialWindow(request(
            rows: [
                row("note:pending", sortAt: 30, pendingNew: true),
                row("note:fallback", sortAt: 20, isMissingTargetFallbackCapable: true),
                row("note:visible", sortAt: 10)
            ],
            readState: TimelineReadStateDraft(scrollAnchorItemKey: "note:pending"),
            policy: .initialRestore(maxVisibleCount: 10)
        ))
        let explicitPending = boundary.initialWindow(request(
            rows: [
                row("note:pending", sortAt: 30, pendingNew: true),
                row("note:visible", sortAt: 10)
            ],
            readState: TimelineReadStateDraft(scrollAnchorItemKey: "note:pending"),
            policy: .explicitUserPendingNew(itemKeys: ["note:pending"], maxVisibleCount: 10)
        ))
        let hidden = boundary.initialWindow(request(
            rows: [
                row("note:hidden", sortAt: 30, hiddenReason: "muted"),
                row("note:visible", sortAt: 10)
            ],
            readState: TimelineReadStateDraft(scrollAnchorItemKey: "note:hidden"),
            policy: .initialRestore(maxVisibleCount: 10)
        ))
        let collapsed = boundary.initialWindow(request(
            rows: [
                row("note:collapsed", sortAt: 30, collapsed: true),
                row("note:visible", sortAt: 10)
            ],
            readState: TimelineReadStateDraft(scrollAnchorItemKey: "note:collapsed"),
            policy: .initialRestore(maxVisibleCount: 10)
        ))
        let fallbackCapable = boundary.initialWindow(request(
            rows: [
                row("note:fallback", sortAt: 30, isMissingTargetFallbackCapable: true),
                row("note:visible", sortAt: 10)
            ],
            readState: TimelineReadStateDraft(scrollAnchorItemKey: "note:fallback"),
            policy: .initialRestore(maxVisibleCount: 10)
        ))

        #expect(defaultPending.visibleItemKeys == ["note:fallback", "note:visible"])
        #expect(defaultPending.anchorItemKey == "note:fallback")
        #expect(defaultPending.diagnostics.fallbackReason == .missingAnchorUsedNewest)
        #expect(defaultPending.diagnostics.excludedPendingNewCount == 1)
        #expect(explicitPending.visibleItemKeys == ["note:pending", "note:visible"])
        #expect(explicitPending.anchorItemKey == "note:pending")
        #expect(explicitPending.diagnostics.fallbackReason == .anchorFound)
        #expect(hidden.visibleItemKeys == ["note:visible"])
        #expect(hidden.anchorItemKey == "note:visible")
        #expect(hidden.diagnostics.fallbackReason == .missingAnchorUsedNewest)
        #expect(hidden.diagnostics.excludedHiddenCount == 1)
        #expect(collapsed.anchorItemKey == "note:collapsed")
        #expect(collapsed.diagnostics.fallbackReason == .anchorFound)
        #expect(collapsed.visibleRows.first?.collapsed == true)
        #expect(fallbackCapable.anchorItemKey == "note:fallback")
        #expect(fallbackCapable.diagnostics.fallbackReason == .anchorFound)
        #expect(fallbackCapable.visibleRows.first?.isMissingTargetFallbackCapable == true)
    }

    @Test("Duplicate item keys dedupe deterministically and record issue")
    func duplicateItemKeysDedupeDeterministicallyAndRecordIssue() {
        let draft = boundary.initialWindow(request(rows: [
            row("note:dup", sourceEventID: "event-newer", sortAt: 30, tieBreakID: "b"),
            row("note:other", sourceEventID: "event-other", sortAt: 20, tieBreakID: "c"),
            row("note:dup", sourceEventID: "event-older", sortAt: 10, tieBreakID: "a")
        ], policy: .initialRestore(maxVisibleCount: 10)))

        #expect(draft.visibleItemKeys == ["note:dup", "note:other"])
        #expect(draft.visibleRows.first?.sourceEventID == eventID("event-newer"))
        #expect(draft.diagnostics.duplicateItemKeyCount == 1)
        #expect(draft.issues.contains { $0.kind == .duplicateItemKey && $0.itemKey == "note:dup" })
    }

    @Test("Invalid item key returns typed issue")
    func invalidItemKeyReturnsTypedIssue() {
        let draft = boundary.initialWindow(request(rows: [
            row("   ", sortAt: 20),
            row("note:valid", sortAt: 10)
        ]))

        #expect(draft.visibleItemKeys == ["note:valid"])
        #expect(draft.issues.contains { $0.kind == .invalidItemKey })
    }

    @Test("Invalid sort key returns typed issue")
    func invalidSortKeyReturnsTypedIssue() {
        let draft = boundary.initialWindow(request(rows: [
            row("note:invalid", sortAt: nil),
            row("note:valid", sortAt: 10)
        ]))

        #expect(draft.visibleItemKeys == ["note:valid"])
        #expect(draft.issues.contains { $0.kind == .invalidSortKey && $0.itemKey == "note:invalid" })
    }

    @Test("Unsafe boundary attempts are rejected as typed issues")
    func unsafeBoundaryAttemptsAreRejectedAsTypedIssues() {
        let unsafePolicy = TimelineVisibleWindowPolicy(
            maxVisibleCount: 10,
            includePendingNew: true,
            pendingNewInclusionReason: nil,
            explicitPendingNewItemKeys: ["note:pending"],
            forcedHiddenItemKeys: ["note:hidden"]
        )
        let draft = boundary.initialWindow(TimelineInitialWindowRequest(
            feedID: .debugHome,
            rows: [
                row("note:pending", sortAt: 30, pendingNew: true),
                row("note:hidden", sortAt: 20, hiddenReason: "muted"),
                row("note:visible", sortAt: 10)
            ],
            readState: nil,
            policy: unsafePolicy,
            attemptsTimelineEntriesOnlyAnchorDerivation: true,
            attemptsReadMarkerAdvance: true
        ))
        let kinds = Set(draft.issues.map(\.kind))

        #expect(draft.visibleItemKeys == ["note:visible"])
        #expect(kinds.isSuperset(of: [
            .pendingNewIncludedWithoutExplicitUserAction,
            .hiddenRowIncludedByMistake,
            .timelineEntriesOnlyAnchorDerivationAttempted,
            .readMarkerAdvanceAttempted
        ]))
        #expect(!draft.diagnostics.readMarkerChanged)
    }

    @Test("Issue coverage matrix covers every TimelineRepositoryBoundaryIssue kind")
    func issueCoverageMatrixCoversEveryTimelineRepositoryBoundaryIssueKind() {
        let entries = repositoryBoundaryIssueCoverageEntries()
        let coveredKinds = Set(entries.map(\.kind))

        #expect(coveredKinds == Set(TimelineRepositoryBoundaryIssue.Kind.allCases))
        #expect(entries.count == coveredKinds.count)

        for entry in entries {
            let draft = boundary.initialWindow(entry.request)
            let issueKinds = Set(draft.issues.map(\.kind))
            let matchingIssues = draft.issues.filter { $0.kind == entry.kind }

            #expect(issueKinds == entry.expectedIssueKinds, "Unexpected issue mix for \(entry.kind): \(issueKinds)")
            #expect(!matchingIssues.isEmpty, "Missing direct negative scenario for \(entry.kind)")
            if let expectedItemKey = entry.expectedItemKey {
                #expect(matchingIssues.contains { $0.itemKey == expectedItemKey })
            }
            if let expectedEventID = entry.expectedEventID {
                #expect(matchingIssues.contains { $0.eventID == expectedEventID })
            }
            entry.validate(draft)
        }
    }

    @Test("Models are Codable Equatable and Sendable where appropriate")
    func modelsAreCodableEquatableAndSendableWhereAppropriate() throws {
        assertSendable(TimelineRepositoryBoundaryProtocol.self)
        assertSendable(TimelineInitialWindowRequest.self)
        assertSendable(TimelineInitialWindowDraft.self)
        assertSendable(TimelineReadStateDraft.self)
        assertSendable(TimelineVisibleWindowPolicy.self)
        assertSendable(TimelineRepositoryFeedItemDraftRow.self)
        assertSendable(TimelineRepositoryFeedItemReason.self)
        assertSendable(TimelineRepositoryBoundaryIssue.self)
        assertSendable(TimelineRepositoryBoundaryDiagnostics.self)
        assertSendable(FixtureTimelineRepositoryBoundary.self)

        let request = request(rows: [row("note:codable")])
        let draft = boundary.initialWindow(request)

        try assertCodableRoundTrip(request)
        try assertCodableRoundTrip(draft)
        try assertCodableRoundTrip(FixtureTimelineRepositoryBoundary())
    }

    @Test("Boundary source imports no DB network relay or resolve actor APIs")
    func boundarySourceImportsNoDBNetworkRelayOrResolveActorAPIs() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/TimelineEngineTypes.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let importLines = source
            .split(separator: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }
            .map(String.init)

        for forbidden in ["GRDB", "Database", "URLSession", "WebSocket", "Relay"] {
            #expect(!importLines.contains("import \(forbidden)"))
        }
        #expect(!source.contains("actor ResolveCoordinator"))
    }

    private func request(
        rows: [TimelineRepositoryFeedItemDraftRow],
        readState: TimelineReadStateDraft? = nil,
        policy: TimelineVisibleWindowPolicy = .initialRestore(maxVisibleCount: 10)
    ) -> TimelineInitialWindowRequest {
        TimelineInitialWindowRequest(
            feedID: .debugHome,
            rows: rows,
            readState: readState,
            policy: policy
        )
    }

    private func row(
        _ itemKey: String,
        sourceEventID: String? = nil,
        subjectEventID: String? = nil,
        reason: TimelineRepositoryFeedItemReason = .author,
        sortAt: Int64? = 10,
        tieBreakID: String? = nil,
        hiddenReason: String? = nil,
        collapsed: Bool = false,
        pendingNew: Bool = false,
        isMissingTargetFallbackCapable: Bool = false
    ) -> TimelineRepositoryFeedItemDraftRow {
        TimelineRepositoryFeedItemDraftRow(
            itemKey: itemKey,
            sourceEventID: eventID(sourceEventID ?? itemKey),
            subjectEventID: subjectEventID.map(eventID),
            reason: reason,
            actorPubkey: "pubkey",
            sortAt: sortAt,
            tieBreakID: tieBreakID ?? itemKey,
            hiddenReason: hiddenReason,
            collapsed: collapsed,
            pendingNew: pendingNew,
            isMissingTargetFallbackCapable: isMissingTargetFallbackCapable
        )
    }

    private func fiveRows() -> [TimelineRepositoryFeedItemDraftRow] {
        [
            row("note:e", sourceEventID: "event-e", sortAt: 50, tieBreakID: "e"),
            row("note:d", sourceEventID: "event-d", sortAt: 40, tieBreakID: "d"),
            row("note:c", sourceEventID: "event-c", sortAt: 30, tieBreakID: "c"),
            row("note:b", sourceEventID: "event-b", sortAt: 20, tieBreakID: "b"),
            row("note:a", sourceEventID: "event-a", sortAt: 10, tieBreakID: "a")
        ]
    }

    private func repositoryBoundaryIssueCoverageEntries() -> [RepositoryBoundaryIssueCoverageEntry] {
        [
            RepositoryBoundaryIssueCoverageEntry(
                kind: .duplicateItemKey,
                request: request(rows: [
                    row("note:dup", sourceEventID: "event-newer", sortAt: 30, tieBreakID: "b"),
                    row("note:other", sourceEventID: "event-other", sortAt: 20, tieBreakID: "c"),
                    row("note:dup", sourceEventID: "event-older", sortAt: 10, tieBreakID: "a")
                ]),
                expectedItemKey: "note:dup",
                expectedEventID: eventID("event-older")
            ) { draft in
                #expect(draft.visibleItemKeys == ["note:dup", "note:other"])
                #expect(draft.diagnostics.duplicateItemKeyCount == 1)
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .missingAnchor,
                request: request(
                    rows: [
                        row("note:newest", sortAt: 20),
                        row("note:older", sortAt: 10)
                    ],
                    readState: TimelineReadStateDraft(scrollAnchorItemKey: "note:missing")
                ),
                expectedItemKey: "note:missing"
            ) { draft in
                #expect(draft.anchorItemKey == "note:newest")
                #expect(draft.anchorSource == .newest)
                #expect(draft.diagnostics.fallbackReason == .missingAnchorUsedNewest)
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .missingScrollAnchorEvent,
                request: request(
                    rows: [
                        row("note:newest", sortAt: 20),
                        row("note:older", sortAt: 10)
                    ],
                    readState: TimelineReadStateDraft(scrollAnchorEventID: eventID("event-missing-anchor"))
                ),
                expectedEventID: eventID("event-missing-anchor")
            ) { draft in
                #expect(draft.anchorItemKey == "note:newest")
                #expect(draft.anchorSource == .newest)
                #expect(draft.diagnostics.fallbackReason == .noReadStateUsedNewest)
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .missingMarker,
                request: request(
                    rows: [
                        row("note:newest", sortAt: 20),
                        row("note:older", sortAt: 10)
                    ],
                    readState: TimelineReadStateDraft(
                        markerItemKey: "note:missing",
                        markerEventID: eventID("event-missing")
                    )
                ),
                expectedItemKey: "note:missing",
                expectedEventID: eventID("event-missing")
            ) { draft in
                #expect(draft.anchorItemKey == "note:newest")
                #expect(draft.anchorSource == .newest)
                #expect(draft.diagnostics.fallbackReason == .missingMarkerUsedNewest)
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .missingLastVisible,
                request: request(
                    rows: [
                        row("note:newest", sortAt: 20),
                        row("note:older", sortAt: 10)
                    ],
                    readState: TimelineReadStateDraft(lastVisibleTopItemKey: "note:missing-visible")
                ),
                expectedItemKey: "note:missing-visible"
            ) { draft in
                #expect(draft.anchorItemKey == "note:newest")
                #expect(draft.anchorSource == .newest)
                #expect(draft.diagnostics.fallbackReason == .noReadStateUsedNewest)
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .invalidSortKey,
                request: request(rows: [
                    row("note:invalid", sourceEventID: "event-invalid-sort", sortAt: nil),
                    row("note:valid", sortAt: 10)
                ]),
                expectedItemKey: "note:invalid",
                expectedEventID: eventID("event-invalid-sort")
            ) { draft in
                #expect(draft.visibleItemKeys == ["note:valid"])
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .invalidItemKey,
                request: request(rows: [
                    row("   ", sourceEventID: "event-invalid-item", sortAt: 20),
                    row("note:valid", sortAt: 10)
                ]),
                expectedItemKey: "   ",
                expectedEventID: eventID("event-invalid-item")
            ) { draft in
                #expect(draft.visibleItemKeys == ["note:valid"])
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .pendingNewIncludedWithoutExplicitUserAction,
                request: request(
                    rows: [
                        row("note:pending", sourceEventID: "event-pending", sortAt: 20, pendingNew: true),
                        row("note:visible", sortAt: 10)
                    ],
                    policy: TimelineVisibleWindowPolicy(
                        maxVisibleCount: 10,
                        includePendingNew: true,
                        pendingNewInclusionReason: nil,
                        explicitPendingNewItemKeys: ["note:pending"]
                    )
                ),
                expectedItemKey: "note:pending",
                expectedEventID: eventID("event-pending")
            ) { draft in
                #expect(draft.visibleItemKeys == ["note:visible"])
                #expect(draft.diagnostics.excludedPendingNewCount == 1)
                #expect(draft.diagnostics.pendingNewIncludedCount == 0)
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .hiddenRowIncludedByMistake,
                request: request(
                    rows: [
                        row("note:hidden", sourceEventID: "event-hidden", sortAt: 20, hiddenReason: "muted"),
                        row("note:visible", sortAt: 10)
                    ],
                    policy: TimelineVisibleWindowPolicy(
                        maxVisibleCount: 10,
                        forcedHiddenItemKeys: ["note:hidden"]
                    )
                ),
                expectedItemKey: "note:hidden",
                expectedEventID: eventID("event-hidden")
            ) { draft in
                #expect(draft.visibleItemKeys == ["note:visible"])
                #expect(draft.diagnostics.excludedHiddenCount == 1)
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .timelineEntriesOnlyAnchorDerivationAttempted,
                request: TimelineInitialWindowRequest(
                    feedID: .debugHome,
                    rows: [row("note:visible")],
                    policy: .initialRestore(maxVisibleCount: 10),
                    attemptsTimelineEntriesOnlyAnchorDerivation: true
                )
            ) { draft in
                #expect(draft.visibleItemKeys == ["note:visible"])
                #expect(!draft.diagnostics.readMarkerChanged)
            },
            RepositoryBoundaryIssueCoverageEntry(
                kind: .readMarkerAdvanceAttempted,
                request: TimelineInitialWindowRequest(
                    feedID: .debugHome,
                    rows: [row("note:visible")],
                    policy: .initialRestore(maxVisibleCount: 10),
                    attemptsReadMarkerAdvance: true
                )
            ) { draft in
                #expect(draft.visibleItemKeys == ["note:visible"])
                #expect(!draft.diagnostics.readMarkerChanged)
            }
        ]
    }

    private func eventID(_ value: String) -> EventID {
        EventID(hex: value)
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    private func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)

        #expect(decoded == value)
    }

    private struct RepositoryBoundaryIssueCoverageEntry {
        var kind: TimelineRepositoryBoundaryIssue.Kind
        var request: TimelineInitialWindowRequest
        var expectedIssueKinds: Set<TimelineRepositoryBoundaryIssue.Kind>
        var expectedItemKey: String?
        var expectedEventID: EventID?
        var validate: (TimelineInitialWindowDraft) -> Void

        init(
            kind: TimelineRepositoryBoundaryIssue.Kind,
            request: TimelineInitialWindowRequest,
            expectedIssueKinds: Set<TimelineRepositoryBoundaryIssue.Kind>? = nil,
            expectedItemKey: String? = nil,
            expectedEventID: EventID? = nil,
            validate: @escaping (TimelineInitialWindowDraft) -> Void = { _ in }
        ) {
            self.kind = kind
            self.request = request
            self.expectedIssueKinds = expectedIssueKinds ?? [kind]
            self.expectedItemKey = expectedItemKey
            self.expectedEventID = expectedEventID
            self.validate = validate
        }
    }
}
