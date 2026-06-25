import DesignSystem
import Foundation
import Testing
@testable import Astrenza

@Suite("Timeline projection contract fixtures")
struct TimelineProjectionContractTests {
    private let scenarios = TimelineProjectionFixtureBuilder.allScenarios
    private let validator = TimelineProjectionContractValidator()

    @Test("Required delayed resolve fixture scenarios exist")
    func requiredDelayedResolveFixtureScenariosExist() {
        let names = Set(scenarios.map(\.name))
        let requiredNames: Set<String> = [
            "textOnly_author_visible",
            "ogp_pending_to_resolved",
            "ogp_pending_to_failed_urlOnlyFallback",
            "media_imeta_present_aspect_reserved",
            "media_imeta_absent_fixed_placeholder",
            "profile_missing_to_resolved_headerOnly",
            "body_mention_profile_resolve_must_not_increase_line_wrap",
            "repost_target_pending_to_resolved",
            "repost_target_deleted_unavailable",
            "quote_target_pending_to_resolved",
            "quote_target_must_not_create_reply_relation",
            "reply_parent_pending_to_resolved_headerOnly",
            "deleted_target_placeholder",
            "muted_target_collapsed_while_visible",
            "pending_new_not_visible_until_user_action",
            "profile_absent_uses_npubFallback",
            "ogp_resolving_keepsReservedLayout",
            "media_blocked_keepsBlockedPlaceholder",
            "quote_target_blocked_unavailableCard",
            "stats_absent_to_resolving_doesNotMutateIdentity",
            "stats_resolving_to_resolved_reconfigureOnly",
            "publish_state_placeholder_localOnly_noReadMarkerChange"
        ]

        #expect(names.isSuperset(of: requiredNames))
    }

    @Test("Contract models are codable equatable and sendable")
    func contractModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineProjectionScenario.self)
        assertSendable(TimelineProjectionInput.self)
        assertSendable(TimelineProjectionExpectedOutput.self)
        assertSendable(TimelineResolveExpectation.self)
        assertSendable(TimelineIdentityExpectation.self)
        assertSendable(TimelineLayoutExpectation.self)
        assertSendable(TimelineVisibilityExpectation.self)
        assertSendable(TimelineFallbackExpectation.self)

        for scenario in scenarios {
            let data = try JSONEncoder().encode(scenario)
            let decoded = try JSONDecoder().decode(TimelineProjectionScenario.self, from: data)

            #expect(decoded == scenario)
        }
    }

    @Test("Every fixture passes the projection contract validator")
    func everyFixturePassesProjectionContractValidator() {
        for scenario in scenarios {
            #expect(validator.validate(scenario).isEmpty, "Invalid scenario: \(scenario.name)")
        }
    }

    @Test("Every fixture uses stable TimelineEntryID item identity")
    func everyFixtureUsesStableTimelineEntryIDItemIdentity() {
        for scenario in scenarios {
            #expect(scenario.input.identity.entryID == scenario.expectedOutput.identity.entryID)
            #expect(scenario.input.identity.entryID.rawValue == scenario.input.identity.itemKey)
            #expect(scenario.expectedOutput.identity.entryID.rawValue == scenario.expectedOutput.identity.itemKey)
        }
    }

    @Test("Delayed resolve transitions preserve itemKey and request reconfigure")
    func delayedResolveTransitionsPreserveItemKeyAndRequestReconfigure() {
        for scenario in scenarios where scenario.hasDelayedResolveTransition {
            #expect(scenario.expectedOutput.mutation.initialEntryID == scenario.expectedOutput.mutation.finalEntryID)
            #expect(scenario.expectedOutput.mutation.initialEntryID.rawValue == scenario.input.identity.itemKey)
            #expect(scenario.expectedOutput.mutation.finalEntryID.rawValue == scenario.expectedOutput.identity.itemKey)
            #expect(scenario.expectedOutput.mutation.expectedMutationStyle == .reconfigure)
            #expect(scenario.expectedOutput.mutation.insertedIDs.isEmpty)
            #expect(scenario.expectedOutput.mutation.deletedIDs.isEmpty)
        }
    }

    @Test("Delayed resolve never expects delete or insert for enrichment targets")
    func delayedResolveNeverExpectsDeleteOrInsertForEnrichmentTargets() {
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

            #expect(scenario.expectedOutput.mutation.expectedMutationStyle == .reconfigure)
            #expect(scenario.expectedOutput.mutation.insertedIDs.isEmpty)
            #expect(scenario.expectedOutput.mutation.deletedIDs.isEmpty)
        }
    }

    @Test("Failed blocked or unavailable resolve keeps the source note visible with fallback")
    func failedBlockedOrUnavailableResolveKeepsSourceNoteVisibleWithFallback() {
        for scenario in scenarios where scenario.expectedOutput.resolveExpectations.contains(where: \.requiresFallback) {
            #expect(scenario.expectedOutput.fallback.keepsSourceNoteVisible)
            #expect(!scenario.expectedOutput.visibility.removesSourceNote)
        }
    }

    @Test("Failed OGP media profile and target resolve fixtures keep fallback coverage")
    func failedOGPMediaProfileAndTargetResolveFixturesKeepFallbackCoverage() {
        let targetsWithFallback = Set(
            scenarios.flatMap { scenario in
                scenario.expectedOutput.resolveExpectations
                    .filter(\.requiresFallback)
                    .map(\.target)
            }
        )

        #expect(targetsWithFallback.isSuperset(of: [
            .linkPreviewOGP,
            .media,
            .profile,
            .repostTarget,
            .quoteTarget
        ]))
    }

    @Test("Quote target does not become reply parent")
    func quoteTargetDoesNotBecomeReplyParent() throws {
        let scenario = try #require(TimelineProjectionFixtureBuilder.scenario(named: "quote_target_must_not_create_reply_relation"))

        #expect(scenario.expectedOutput.resolveExpectations.contains { $0.target == .quoteTarget })
        #expect(!scenario.expectedOutput.mutation.quoteCreatesReplyRelation)
        #expect(scenario.expectedOutput.layout.replyHeaderMode == .absent)
    }

    @Test("Reply parent in Home remains one line header only")
    func replyParentInHomeRemainsOneLineHeaderOnly() throws {
        let scenario = try #require(TimelineProjectionFixtureBuilder.scenario(named: "reply_parent_pending_to_resolved_headerOnly"))

        #expect(scenario.expectedOutput.layout.rowKind == .home)
        #expect(scenario.expectedOutput.layout.replyHeaderMode == .oneLine)
        #expect(!scenario.expectedOutput.layout.allowsInlineParentPreviewInHome)
    }

    @Test("Home visible delayed resolve fixtures cannot change height after first display")
    func homeVisibleDelayedResolveFixturesCannotChangeHeightAfterFirstDisplay() {
        for scenario in scenarios where scenario.hasDelayedResolveTransition {
            guard scenario.expectedOutput.layout.rowKind == .home,
                  scenario.expectedOutput.visibility.isVisibleInHome,
                  !scenario.expectedOutput.layout.isDetailOnly
            else {
                continue
            }

            #expect(!scenario.expectedOutput.layout.canChangeHeightAfterFirstDisplay)
            #expect(scenario.expectedOutput.layout.noUnlimitedHeightGrowthAfterResolve)
        }
    }

    @Test("Pending new fixture is excluded until user action")
    func pendingNewFixtureIsExcludedUntilUserAction() throws {
        let scenario = try #require(TimelineProjectionFixtureBuilder.scenario(named: "pending_new_not_visible_until_user_action"))

        #expect(scenario.input.isPendingNew)
        #expect(!scenario.input.userActionAllowsPendingNewInsertion)
        #expect(!scenario.expectedOutput.visibility.includedInVisibleSnapshot)
        #expect(!scenario.expectedOutput.mutation.pendingNewInsertedIntoVisibleSnapshot)
    }

    @Test("Fixture suite covers every resolve state")
    func fixtureSuiteCoversEveryResolveState() {
        let states = Set(scenarios.flatMap { scenario in
            scenario.expectedOutput.resolveExpectations.flatMap { expectation in
                [expectation.initialState, expectation.expectedState]
            }
        })

        #expect(states.isSuperset(of: Set(TimelineProjectionResolveState.allCases)))
    }

    @Test("Fixture suite covers every required delayed resolve target")
    func fixtureSuiteCoversEveryRequiredDelayedResolveTarget() {
        let targets = Set(scenarios.flatMap { scenario in
            scenario.expectedOutput.resolveExpectations.map(\.target)
        })

        #expect(targets.isSuperset(of: Set(TimelineDelayedResolveTarget.allCases)))
    }

    @Test("Stats and publish placeholder fixtures reconfigure without identity or read marker changes")
    func statsAndPublishPlaceholderFixturesReconfigureWithoutIdentityOrReadMarkerChanges() throws {
        let scenarios = try [
            fixture(named: "stats_absent_to_resolving_doesNotMutateIdentity"),
            fixture(named: "stats_resolving_to_resolved_reconfigureOnly"),
            fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange")
        ]

        for scenario in scenarios {
            #expect(scenario.input.identity.entryID == scenario.expectedOutput.identity.entryID)
            #expect(scenario.expectedOutput.mutation.initialEntryID == scenario.expectedOutput.mutation.finalEntryID)
            #expect(scenario.expectedOutput.mutation.expectedMutationStyle == .reconfigure)
            #expect(scenario.expectedOutput.mutation.insertedIDs.isEmpty)
            #expect(scenario.expectedOutput.mutation.deletedIDs.isEmpty)
            #expect(!scenario.expectedOutput.mutation.readMarkerChanged)
        }

        let publishState = try fixture(named: "publish_state_placeholder_localOnly_noReadMarkerChange")
        #expect(publishState.expectedOutput.resolveExpectations.allSatisfy { expectation in
            expectation.target == .publishStatePlaceholder && !expectation.requiresRemoteWork
        })
    }

    @Test("Read marker is unchanged for all fixture transitions")
    func readMarkerIsUnchangedForAllFixtureTransitions() {
        for scenario in scenarios {
            #expect(!scenario.expectedOutput.mutation.readMarkerChanged)
        }
    }

    @Test("Fixtures reuse DesignSystem layout contract modes")
    func fixturesReuseDesignSystemLayoutContractModes() throws {
        let ogp = try #require(TimelineProjectionFixtureBuilder.scenario(named: "ogp_pending_to_resolved"))
        let quote = try #require(TimelineProjectionFixtureBuilder.scenario(named: "quote_target_pending_to_resolved"))
        let reply = try #require(TimelineProjectionFixtureBuilder.scenario(named: "reply_parent_pending_to_resolved_headerOnly"))
        let mention = try #require(TimelineProjectionFixtureBuilder.scenario(named: "body_mention_profile_resolve_must_not_increase_line_wrap"))

        #expect(ogp.expectedOutput.layout.linkPreviewMode == .fixedCompactCard)
        #expect(quote.expectedOutput.layout.quoteMode == .collapsedCard)
        #expect(reply.expectedOutput.layout.replyHeaderMode == .oneLine)
        #expect(mention.expectedOutput.layout.bodyMentionRendering == .resolvedDisplayNameWithFallback)
    }

    @Test("Validator rejects unstable identity across delayed resolve")
    func validatorRejectsUnstableIdentityAcrossDelayedResolve() throws {
        var scenario = try fixture(named: "ogp_pending_to_resolved")
        scenario.expectedOutput.identity.itemKey += ":resolved"
        scenario.expectedOutput.mutation.finalEntryID = scenario.expectedOutput.identity.entryID

        expectIssue(.unstableIdentity, in: scenario)
    }

    @Test("Validator rejects delayed resolve mutation styles other than reconfigure")
    func validatorRejectsDelayedResolveMutationStylesOtherThanReconfigure() throws {
        var scenario = try fixture(named: "ogp_pending_to_resolved")
        scenario.expectedOutput.mutation.expectedMutationStyle = .snapshot

        expectIssue(.delayedResolveMustReconfigure, in: scenario)
    }

    @Test("Validator rejects read marker changes during resolve")
    func validatorRejectsReadMarkerChangesDuringResolve() throws {
        var scenario = try fixture(named: "profile_missing_to_resolved_headerOnly")
        scenario.expectedOutput.mutation.readMarkerChanged = true

        expectIssue(.readMarkerMustNotChange, in: scenario)
    }

    @Test("Validator rejects pending new visibility before explicit user action")
    func validatorRejectsPendingNewVisibilityBeforeExplicitUserAction() throws {
        var scenario = try fixture(named: "pending_new_not_visible_until_user_action")
        scenario.expectedOutput.visibility.includedInVisibleSnapshot = true
        scenario.expectedOutput.mutation.pendingNewInsertedIntoVisibleSnapshot = true

        expectIssue(.pendingNewMustWaitForUserAction, in: scenario)
    }

    @Test("Validator rejects failed or blocked resolve hiding the source note")
    func validatorRejectsFailedOrBlockedResolveHidingTheSourceNote() throws {
        for name in [
            "ogp_pending_to_failed_urlOnlyFallback",
            "media_blocked_keepsBlockedPlaceholder",
            "profile_missing_to_failed_npubFallback",
            "quote_target_blocked_unavailableCard"
        ] {
            var scenario = try fixture(named: name)
            scenario.expectedOutput.fallback.keepsSourceNoteVisible = false

            expectIssue(.failedResolveMustKeepSourceNoteVisible, in: scenario)
        }
    }

    @Test("Validator rejects quote target becoming reply parent")
    func validatorRejectsQuoteTargetBecomingReplyParent() throws {
        var scenario = try fixture(named: "quote_target_pending_to_resolved")
        scenario.expectedOutput.mutation.quoteCreatesReplyRelation = true

        expectIssue(.quoteMustNotCreateReplyRelation, in: scenario)
    }

    @Test("Validator rejects inline reply parent body in Home")
    func validatorRejectsInlineReplyParentBodyInHome() throws {
        var scenario = try fixture(named: "reply_parent_pending_to_resolved_headerOnly")
        scenario.expectedOutput.layout.contract.replyHeaderMode = .inlineParentInDetail
        scenario.expectedOutput.layout.contract.allowsInlineParentPreviewInHome = true

        expectIssue(.homeReplyParentMustBeHeaderOnly, in: scenario)
    }

    @Test("Validator rejects Home visible delayed resolve height growth")
    func validatorRejectsHomeVisibleDelayedResolveHeightGrowth() throws {
        var scenario = try fixture(named: "ogp_pending_to_resolved")
        scenario.expectedOutput.layout.contract.canChangeHeightAfterFirstDisplay = true
        scenario.expectedOutput.layout.noUnlimitedHeightGrowthAfterResolve = false

        expectIssue(.homeVisibleResolveMustNotChangeHeight, in: scenario)
    }

    @Test("Validator rejects visible rows without layout contract")
    func validatorRejectsVisibleRowsWithoutLayoutContract() throws {
        var scenario = try fixture(named: "textOnly_author_visible")
        scenario.expectedOutput.layout.hasLayoutContract = false

        expectIssue(.visibleRowRequiresLayoutContract, in: scenario)
    }

    @Test("Validator rejects delete or insert mutation expectations for delayed resolve targets")
    func validatorRejectsDeleteOrInsertMutationExpectationsForDelayedResolveTargets() throws {
        let fixtureNames = [
            "profile_missing_to_resolved_headerOnly",
            "body_mention_profile_resolve_must_not_increase_line_wrap",
            "media_imeta_present_aspect_reserved",
            "ogp_pending_to_resolved",
            "repost_target_pending_to_resolved",
            "quote_target_pending_to_resolved",
            "reply_parent_pending_to_resolved_headerOnly",
            "stats_resolving_to_resolved_reconfigureOnly",
            "publish_state_placeholder_localOnly_noReadMarkerChange"
        ]

        for name in fixtureNames {
            var scenario = try fixture(named: name)
            scenario.expectedOutput.mutation.insertedIDs = [TimelineEntryID(rawValue: "\(name):inserted")]
            scenario.expectedOutput.mutation.deletedIDs = [scenario.expectedOutput.mutation.initialEntryID]
            scenario.expectedOutput.mutation.expectedMutationStyle = .reconfigure

            expectIssue(.delayedResolveMustNotInsertOrDelete, in: scenario)
        }
    }

    private func fixture(named name: String) throws -> TimelineProjectionScenario {
        try #require(TimelineProjectionFixtureBuilder.scenario(named: name))
    }

    private func expectIssue(
        _ rule: TimelineProjectionValidationIssue.Rule,
        in scenario: TimelineProjectionScenario
    ) {
        let issues = validator.validate(scenario).map(\.rule)

        #expect(issues.contains(rule), "Expected \(rule), got \(issues)")
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}
}
