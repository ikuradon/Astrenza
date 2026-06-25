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
            "pending_new_not_visible_until_user_action"
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
            .replyParentRoot
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

    @Test("Failed or unavailable resolve keeps the source note visible with fallback")
    func failedOrUnavailableResolveKeepsSourceNoteVisibleWithFallback() {
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

    private func assertSendable<T: Sendable>(_ type: T.Type) {}
}
