import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineRepositoryStore diagnostics mapping")
struct TimelineRepositoryStoreDiagnosticsMappingTests {
    @Test("coverage matrix maps every Core store issue kind")
    func coverageMatrixMapsEveryCoreStoreIssueKind() {
        let entries = TimelineRepositoryStoreDiagnosticsMapper.coverageEntries
        let coveredKinds = Set(entries.map(\.coreKind))

        #expect(coveredKinds == Set(TimelineRepositoryStoreIssue.Kind.allCases))
        #expect(entries.count == coveredKinds.count)
        #expect(entries.allSatisfy { !$0.coverageName.isEmpty })
    }

    @Test("all Core issue kinds map to app-owned diagnostic records")
    func allCoreIssueKindsMapToAppOwnedDiagnosticRecords() throws {
        for kind in TimelineRepositoryStoreIssue.Kind.allCases {
            let record = try #require(TimelineRepositoryStoreDiagnosticsMapper.record(
                for: issue(kind, itemKey: "note:\(kind.rawValue)"),
                diagnostics: diagnostics()
            ))

            #expect(record.issue.kind.rawValue == kind.rawValue)
            #expect(record.issue.feedID == FeedID(rawValue: 10))
            #expect(record.issue.itemKey == "note:\(kind.rawValue)")
            #expect(record.readMarkerChanged == false)
            #expect(record.requiresNetworkWork == false)
            #expect(record.requiresDBWork == false)
            #expect(record.performedLocalDBRead == true)
        }
    }

    @Test("hidden anchor maps to fallback diagnostic with hidden-specific reason")
    func hiddenAnchorMapsToFallbackDiagnosticWithHiddenSpecificReason() throws {
        let record = try mappedRecord(.hiddenAnchor, itemKey: "note:hidden-anchor")

        #expect(record.category == .restoreFallback)
        #expect(record.fallbackRelevance == .hiddenAnchor)
        #expect(record.disposition == .debugOnly)
        #expect(record.boundaryIssue?.kind == .missingAnchor)
        #expect(record.boundaryIssue?.itemKey == "note:hidden-anchor")
    }

    @Test("pending anchor maps to pending policy diagnostic")
    func pendingAnchorMapsToPendingPolicyDiagnostic() throws {
        let record = try mappedRecord(.pendingAnchor, itemKey: "note:pending-anchor")

        #expect(record.category == .pendingNewPolicy)
        #expect(record.fallbackRelevance == .pendingAnchor)
        #expect(record.disposition == .debugOnly)
        #expect(record.boundaryIssue?.kind == .missingAnchor)
        #expect(record.boundaryIssue?.itemKey == "note:pending-anchor")
    }

    @Test("invalid sort key maps to persisted-row diagnostic")
    func invalidSortKeyMapsToPersistedRowDiagnostic() throws {
        let record = try mappedRecord(.invalidSortKey, itemKey: "note:invalid-sort")

        #expect(record.category == .localDataIntegrity)
        #expect(record.fallbackRelevance == .none)
        #expect(record.disposition == .releaseBlocking)
        #expect(record.boundaryIssue?.kind == .invalidSortKey)
        #expect(record.boundaryIssue?.itemKey == "note:invalid-sort")
    }

    @Test("malformed read state maps to read-state diagnostic without crashing")
    func malformedReadStateMapsToReadStateDiagnosticWithoutCrashing() throws {
        let record = try mappedRecord(.malformedReadState, itemKey: nil)

        #expect(record.category == .readStateRestore)
        #expect(record.fallbackRelevance == .readStateSanitized)
        #expect(record.disposition == .releaseBlocking)
        #expect(record.boundaryIssue == nil)
        #expect(record.readMarkerChanged == false)
    }

    @Test("missing feed maps to empty-feed diagnostic")
    func missingFeedMapsToEmptyFeedDiagnostic() throws {
        let record = try mappedRecord(.missingFeed, itemKey: nil)

        #expect(record.category == .emptyFeed)
        #expect(record.fallbackRelevance == .emptyFeed)
        #expect(record.disposition == .debugOnly)
        #expect(record.boundaryIssue == nil)
    }

    @Test("records never imply snapshot mutation or read marker advancement")
    func recordsNeverImplySnapshotMutationOrReadMarkerAdvancement() {
        let records = TimelineRepositoryStoreDiagnosticsMapper.records(
            for: TimelineRepositoryStoreIssue.Kind.allCases.map { issue($0, itemKey: "note:\($0.rawValue)") },
            diagnostics: diagnostics()
        )

        #expect(records.count == TimelineRepositoryStoreIssue.Kind.allCases.count)
        #expect(records.allSatisfy { $0.readMarkerChanged == false })
        #expect(records.allSatisfy { $0.snapshotMutationStyle == nil })
        #expect(records.allSatisfy { $0.insertsVisibleSnapshotItems == false })
        #expect(records.allSatisfy { $0.deletesVisibleSnapshotItems == false })
    }

    @Test("records stay local and carry no sensitive payload keys")
    func recordsStayLocalAndCarryNoSensitivePayloadKeys() {
        let records = TimelineRepositoryStoreDiagnosticsMapper.records(
            for: TimelineRepositoryStoreIssue.Kind.allCases.map { issue($0, itemKey: "note:\($0.rawValue)") },
            diagnostics: diagnostics()
        )

        #expect(records.allSatisfy { $0.externalDestinationCreated == false })
        #expect(records.allSatisfy { $0.localDebugOnly == true })
        #expect(records.allSatisfy { $0.sensitivePayloadKeys.isEmpty })
        #expect(records.allSatisfy { $0.requiresNetworkWork == false })
    }

    @Test("diagnostic records are Codable Equatable and Sendable")
    func diagnosticRecordsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineRepositoryStoreIssueEnvelope.self)
        assertSendable(TimelineRepositoryStoreDiagnosticRecord.self)
        assertSendable(TimelineRepositoryStoreIssueCoverageEntry.self)

        let record = try mappedRecord(.invalidPersistedReason, itemKey: "note:bad-reason")
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TimelineRepositoryStoreDiagnosticRecord.self, from: data)

        #expect(decoded == record)
    }

    private func mappedRecord(
        _ kind: TimelineRepositoryStoreIssue.Kind,
        itemKey: String?
    ) throws -> TimelineRepositoryStoreDiagnosticRecord {
        try #require(TimelineRepositoryStoreDiagnosticsMapper.record(
            for: issue(kind, itemKey: itemKey),
            diagnostics: diagnostics()
        ))
    }

    private func issue(
        _ kind: TimelineRepositoryStoreIssue.Kind,
        itemKey: String?
    ) -> TimelineRepositoryStoreIssue {
        TimelineRepositoryStoreIssue(kind: kind, feedID: 10, itemKey: itemKey)
    }

    private func diagnostics() -> TimelineRepositoryStoreDiagnostics {
        TimelineRepositoryStoreDiagnostics(
            totalFeedItemRowCount: 4,
            sqlVisibleRowCount: 2,
            excludedHiddenCount: 1,
            excludedPendingNewCount: 1,
            pendingNewIncludedCount: 0,
            readStatePresent: true,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresExternalMutation: false,
            performedLocalDBRead: true,
            resolveJobRowCount: 0,
            diagnosticRowCount: 0
        )
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
