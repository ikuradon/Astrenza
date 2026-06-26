import DesignSystem
import Foundation

protocol TimelineProjectionAdapterProtocol: Sendable {
    func project(_ input: TimelineProjectionAdapterInput) -> TimelineProjectionAdapterOutput
}

enum TimelineProjectionAdapterSurface: String, CaseIterable, Codable, Sendable {
    case home
    case detail
    case thread
}

struct TimelineProjectionAdapterInput: Equatable, Codable, Sendable {
    var scenario: TimelineProjectionScenario
    var surface: TimelineProjectionAdapterSurface
    var currentVisibleEntryIDs: [TimelineEntryID]
    var pendingNewEntryIDs: [TimelineEntryID]
    var userActionAllowsPendingNewInsertion: Bool

    init(
        scenario: TimelineProjectionScenario,
        surface: TimelineProjectionAdapterSurface = .home,
        currentVisibleEntryIDs: [TimelineEntryID] = [],
        pendingNewEntryIDs: [TimelineEntryID] = [],
        userActionAllowsPendingNewInsertion: Bool? = nil
    ) {
        self.scenario = scenario
        self.surface = surface
        self.currentVisibleEntryIDs = currentVisibleEntryIDs
        self.pendingNewEntryIDs = pendingNewEntryIDs
        self.userActionAllowsPendingNewInsertion = userActionAllowsPendingNewInsertion
            ?? scenario.input.userActionAllowsPendingNewInsertion
    }
}

struct TimelineProjectionAdapterOutput: Equatable, Codable, Sendable {
    var scenarioName: String
    var surface: TimelineProjectionAdapterSurface
    var entryID: TimelineEntryID?
    var itemKey: String?
    var sourceEventID: EventID?
    var subjectEventID: EventID?
    var sortAt: Int64?
    var tieBreakID: String?
    var feedItemReason: TimelineProjectionFeedItemReason?
    var resolveExpectations: [TimelineResolveExpectation]
    var mutationExpectation: TimelineProjectionMutationExpectation?
    var layoutDecision: TimelineProjectionLayoutDecision?
    var visibilityDecision: TimelineProjectionVisibilityDecision?
    var fallback: TimelineFallbackExpectation?
    var diagnostics: TimelineProjectionAdapterDiagnostics
    var issues: [TimelineProjectionAdapterIssue]

    var isProjected: Bool {
        issues.isEmpty && entryID != nil
    }
}

struct TimelineProjectionAdapterIssue: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case contractValidation
    }

    var scenarioName: String
    var kind: Kind
    var contractRule: TimelineProjectionValidationIssue.Rule?
}

struct TimelineProjectionAdapterDiagnostics: Equatable, Codable, Sendable {
    var scenarioName: String
    var validatedByContractValidator: Bool
    var contractIssueCount: Int
    var readMarkerChanged: Bool
    var pendingNewVisible: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
}

struct TimelineProjectionMutationExpectation: Equatable, Codable, Sendable {
    enum Style: String, Codable, Sendable {
        case none
        case reconfigure
        case insertOnlyForExplicitUserPendingNewAction
        case neverDeleteInsertForDelayedResolve
    }

    var style: Style
    var delayedResolveStyle: Style?
    var initialEntryID: TimelineEntryID
    var finalEntryID: TimelineEntryID
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]
    var allowsDeleteInsertForDelayedResolve: Bool
    var readMarkerChanged: Bool
    var pendingNewInsertedIntoVisibleSnapshot: Bool
    var quoteCreatesReplyRelation: Bool
}

struct TimelineProjectionLayoutDecision: Equatable, Codable, Sendable {
    var surface: TimelineProjectionAdapterSurface
    var contract: TimelineRowLayoutContract
    var noUnlimitedHeightGrowthAfterResolve: Bool
    var isDetailOnly: Bool
    var hasLayoutContract: Bool
}

struct TimelineProjectionVisibilityDecision: Equatable, Codable, Sendable {
    var mode: TimelineVisibilityMode
    var includedInVisibleSnapshot: Bool
    var pendingNewVisible: Bool
    var removesSourceNote: Bool
    var fallbackMode: TimelineFallbackMode
}

struct FixtureBackedTimelineProjectionAdapter: TimelineProjectionAdapterProtocol {
    private let validator: TimelineProjectionContractValidator

    init(validator: TimelineProjectionContractValidator = TimelineProjectionContractValidator()) {
        self.validator = validator
    }

    func project(_ input: TimelineProjectionAdapterInput) -> TimelineProjectionAdapterOutput {
        let contractIssues = validator.validate(input.scenario)
        var diagnostics = TimelineProjectionAdapterDiagnostics(
            scenarioName: input.scenario.name,
            validatedByContractValidator: true,
            contractIssueCount: contractIssues.count,
            readMarkerChanged: false,
            pendingNewVisible: false,
            requiresNetworkWork: false,
            requiresDBWork: false
        )

        guard contractIssues.isEmpty else {
            return TimelineProjectionAdapterOutput(
                scenarioName: input.scenario.name,
                surface: input.surface,
                entryID: nil,
                itemKey: nil,
                sourceEventID: nil,
                subjectEventID: nil,
                sortAt: nil,
                tieBreakID: nil,
                feedItemReason: nil,
                resolveExpectations: [],
                mutationExpectation: nil,
                layoutDecision: nil,
                visibilityDecision: nil,
                fallback: nil,
                diagnostics: diagnostics,
                issues: contractIssues.map(Self.issue)
            )
        }

        let expectedOutput = input.scenario.expectedOutput
        let identity = expectedOutput.identity
        let pendingNewVisible = pendingNewVisible(for: input, entryID: identity.entryID)
        diagnostics.pendingNewVisible = pendingNewVisible

        return TimelineProjectionAdapterOutput(
            scenarioName: input.scenario.name,
            surface: input.surface,
            entryID: identity.entryID,
            itemKey: identity.itemKey,
            sourceEventID: identity.sourceEventID,
            subjectEventID: identity.subjectEventID,
            sortAt: identity.sortAt,
            tieBreakID: identity.tieBreakID,
            feedItemReason: identity.feedItemReason,
            resolveExpectations: expectedOutput.resolveExpectations,
            mutationExpectation: mutationExpectation(
                for: input,
                expectedOutput: expectedOutput,
                pendingNewVisible: pendingNewVisible
            ),
            layoutDecision: layoutDecision(
                for: expectedOutput.layout,
                surface: input.surface
            ),
            visibilityDecision: visibilityDecision(
                for: expectedOutput.visibility,
                fallback: expectedOutput.fallback,
                pendingNewVisible: pendingNewVisible,
                isPendingNew: input.scenario.input.isPendingNew
            ),
            fallback: expectedOutput.fallback,
            diagnostics: diagnostics,
            issues: []
        )
    }

    private static func issue(
        from validationIssue: TimelineProjectionValidationIssue
    ) -> TimelineProjectionAdapterIssue {
        TimelineProjectionAdapterIssue(
            scenarioName: validationIssue.scenarioName,
            kind: .contractValidation,
            contractRule: validationIssue.rule
        )
    }

    private func pendingNewVisible(
        for input: TimelineProjectionAdapterInput,
        entryID: TimelineEntryID
    ) -> Bool {
        input.scenario.input.isPendingNew
            && input.userActionAllowsPendingNewInsertion
            && input.pendingNewEntryIDs.contains(entryID)
    }

    private func mutationExpectation(
        for input: TimelineProjectionAdapterInput,
        expectedOutput: TimelineProjectionExpectedOutput,
        pendingNewVisible: Bool
    ) -> TimelineProjectionMutationExpectation {
        let contractMutation = expectedOutput.mutation
        let hasDelayedResolveTransition = expectedOutput.resolveExpectations.contains { expectation in
            expectation.isDelayedResolveTransition
        }
        let style: TimelineProjectionMutationExpectation.Style
        let insertedIDs: [TimelineEntryID]

        if pendingNewVisible {
            style = .insertOnlyForExplicitUserPendingNewAction
            insertedIDs = [expectedOutput.identity.entryID]
        } else if hasDelayedResolveTransition || contractMutation.expectedMutationStyle == .reconfigure {
            style = .reconfigure
            insertedIDs = contractMutation.insertedIDs
        } else {
            style = .none
            insertedIDs = []
        }

        return TimelineProjectionMutationExpectation(
            style: style,
            delayedResolveStyle: hasDelayedResolveTransition ? .neverDeleteInsertForDelayedResolve : nil,
            initialEntryID: contractMutation.initialEntryID,
            finalEntryID: contractMutation.finalEntryID,
            insertedIDs: insertedIDs,
            deletedIDs: pendingNewVisible ? [] : contractMutation.deletedIDs,
            allowsDeleteInsertForDelayedResolve: false,
            readMarkerChanged: contractMutation.readMarkerChanged,
            pendingNewInsertedIntoVisibleSnapshot: pendingNewVisible,
            quoteCreatesReplyRelation: contractMutation.quoteCreatesReplyRelation
        )
    }

    private func layoutDecision(
        for layout: TimelineLayoutExpectation,
        surface: TimelineProjectionAdapterSurface
    ) -> TimelineProjectionLayoutDecision {
        TimelineProjectionLayoutDecision(
            surface: surface,
            contract: layout.contract,
            noUnlimitedHeightGrowthAfterResolve: layout.noUnlimitedHeightGrowthAfterResolve,
            isDetailOnly: layout.isDetailOnly,
            hasLayoutContract: layout.hasLayoutContract
        )
    }

    private func visibilityDecision(
        for visibility: TimelineVisibilityExpectation,
        fallback: TimelineFallbackExpectation,
        pendingNewVisible: Bool,
        isPendingNew: Bool
    ) -> TimelineProjectionVisibilityDecision {
        TimelineProjectionVisibilityDecision(
            mode: visibility.mode,
            includedInVisibleSnapshot: isPendingNew
                ? pendingNewVisible
                : visibility.includedInVisibleSnapshot,
            pendingNewVisible: pendingNewVisible,
            removesSourceNote: visibility.removesSourceNote,
            fallbackMode: fallback.mode
        )
    }
}
