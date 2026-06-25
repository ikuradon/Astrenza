import DesignSystem
import Foundation

enum TimelineProjectionFixtureBuilder {
    static let allScenarios: [TimelineProjectionScenario] = [
        scenario(
            name: "textOnly_author_visible",
            sourceSeed: "a",
            sortAt: 1_800,
            reason: .author,
            layout: homeLayout()
        ),
        scenario(
            name: "ogp_pending_to_resolved",
            sourceSeed: "b",
            sortAt: 1_790,
            reason: .author,
            resolveExpectations: [
                resolve(.linkPreviewOGP, from: .pending, to: .resolved)
            ],
            layout: homeLayout(linkPreviewMode: .fixedCompactCard),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "ogp_pending_to_failed_urlOnlyFallback",
            sourceSeed: "c",
            sortAt: 1_780,
            reason: .author,
            resolveExpectations: [
                resolve(.linkPreviewOGP, from: .pending, to: .failed)
            ],
            layout: homeLayout(linkPreviewMode: .urlOnly),
            fallback: fallback(.urlOnly),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "media_imeta_present_aspect_reserved",
            sourceSeed: "d",
            sortAt: 1_770,
            reason: .author,
            resolveExpectations: [
                resolve(.media, from: .pending, to: .resolved)
            ],
            layout: homeLayout(
                reservedMediaAspectRatio: 4.0 / 3.0,
                reservedMediaHeight: 240
            ),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "media_imeta_absent_fixed_placeholder",
            sourceSeed: "e",
            sortAt: 1_760,
            reason: .author,
            resolveExpectations: [
                resolve(.media, from: .pending, to: .failed)
            ],
            layout: homeLayout(
                reservedMediaAspectRatio: 16.0 / 9.0,
                reservedMediaHeight: 180
            ),
            fallback: fallback(.fixedMediaPlaceholder),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "profile_missing_to_resolved_headerOnly",
            sourceSeed: "f",
            sortAt: 1_750,
            reason: .author,
            resolveExpectations: [
                resolve(.profile, from: .pending, to: .resolved)
            ],
            layout: homeLayout(),
            fallback: fallback(.npubHeaderOnly),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "profile_missing_to_failed_npubFallback",
            sourceSeed: "f",
            sortAt: 1_745,
            reason: .author,
            resolveExpectations: [
                resolve(.profile, from: .pending, to: .failed)
            ],
            layout: homeLayout(),
            fallback: fallback(.npubHeaderOnly),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "body_mention_profile_resolve_must_not_increase_line_wrap",
            sourceSeed: "0",
            sortAt: 1_740,
            reason: .mention,
            resolveExpectations: [
                resolve(.bodyMention, from: .pending, to: .resolved)
            ],
            layout: homeLayout(
                bodyMentionRendering: .resolvedDisplayNameWithFallback,
                maxBodyLinesInCollapsedMode: 8
            ),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "repost_target_pending_to_resolved",
            sourceSeed: "1",
            subjectSeed: "2",
            sortAt: 1_730,
            reason: .repost,
            resolveExpectations: [
                resolve(.repostTarget, from: .pending, to: .resolved)
            ],
            layout: homeLayout(),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "repost_target_deleted_unavailable",
            sourceSeed: "3",
            subjectSeed: "4",
            sortAt: 1_720,
            reason: .repost,
            resolveExpectations: [
                resolve(.repostTarget, from: .pending, to: .unavailable)
            ],
            layout: homeLayout(),
            visibility: visibility(.unavailablePlaceholder),
            fallback: fallback(.targetUnavailablePlaceholder),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "quote_target_pending_to_resolved",
            sourceSeed: "5",
            subjectSeed: "6",
            sortAt: 1_710,
            reason: .quote,
            resolveExpectations: [
                resolve(.quoteTarget, from: .pending, to: .resolved)
            ],
            layout: homeLayout(quoteMode: .collapsedCard),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "quote_target_must_not_create_reply_relation",
            sourceSeed: "7",
            subjectSeed: "8",
            sortAt: 1_700,
            reason: .quote,
            resolveExpectations: [
                resolve(.quoteTarget, from: .pending, to: .resolved)
            ],
            layout: homeLayout(
                quoteMode: .collapsedCard,
                replyHeaderMode: .absent
            ),
            mutationStyle: .reconfigure,
            quoteCreatesReplyRelation: false
        ),
        scenario(
            name: "reply_parent_pending_to_resolved_headerOnly",
            sourceSeed: "9",
            subjectSeed: "a",
            sortAt: 1_690,
            reason: .reply,
            resolveExpectations: [
                resolve(.replyParentRoot, from: .pending, to: .resolved)
            ],
            layout: homeLayout(replyHeaderMode: .oneLine),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "deleted_target_placeholder",
            sourceSeed: "b",
            subjectSeed: "c",
            sortAt: 1_680,
            reason: .quote,
            resolveExpectations: [
                resolve(.quoteTarget, from: .pending, to: .unavailable)
            ],
            layout: homeLayout(quoteMode: .collapsedCard),
            visibility: visibility(.deletedPlaceholder),
            fallback: fallback(.deletedPlaceholder),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "muted_target_collapsed_while_visible",
            sourceSeed: "d",
            sortAt: 1_670,
            reason: .author,
            layout: homeLayout(),
            visibility: visibility(.mutedPlaceholder),
            fallback: fallback(.mutedCollapsed),
            mutationStyle: .reconfigure
        ),
        scenario(
            name: "pending_new_not_visible_until_user_action",
            sourceSeed: "e",
            sortAt: 1_660,
            reason: .author,
            layout: homeLayout(),
            visibility: visibility(.visible, includedInVisibleSnapshot: false),
            isPendingNew: true,
            userActionAllowsPendingNewInsertion: false,
            mutationStyle: .snapshot
        )
    ]

    static func scenario(named name: String) -> TimelineProjectionScenario? {
        allScenarios.first { $0.name == name }
    }

    private static func scenario(
        name: String,
        sourceSeed: String,
        subjectSeed: String? = nil,
        sortAt: Int64,
        reason: TimelineProjectionFeedItemReason,
        resolveExpectations: [TimelineResolveExpectation] = [],
        layout: TimelineLayoutExpectation,
        visibility: TimelineVisibilityExpectation = visibility(.visible),
        fallback: TimelineFallbackExpectation = fallback(.none),
        isPendingNew: Bool = false,
        userActionAllowsPendingNewInsertion: Bool = false,
        mutationStyle: TimelineMutationStyle? = nil,
        quoteCreatesReplyRelation: Bool = false
    ) -> TimelineProjectionScenario {
        let identity = TimelineIdentityExpectation(
            itemKey: "home:\(sortAt):\(name)",
            sourceEventID: eventID(repeating: sourceSeed),
            subjectEventID: subjectSeed.map { eventID(repeating: $0) },
            sortAt: sortAt,
            tieBreakID: "\(sortAt):\(sourceSeed):\(name)",
            feedItemReason: reason
        )
        let expectedMutationStyle = mutationStyle ?? (resolveExpectations.contains { $0.isDelayedResolveTransition } ? .reconfigure : .snapshot)
        let mutation = TimelineMutationExpectation(
            initialEntryID: identity.entryID,
            finalEntryID: identity.entryID,
            expectedMutationStyle: expectedMutationStyle,
            insertedIDs: [],
            deletedIDs: [],
            readMarkerChanged: false,
            pendingNewInsertedIntoVisibleSnapshot: false,
            quoteCreatesReplyRelation: quoteCreatesReplyRelation
        )

        return TimelineProjectionScenario(
            name: name,
            input: TimelineProjectionInput(
                identity: identity,
                resolveExpectations: resolveExpectations,
                isPendingNew: isPendingNew,
                userActionAllowsPendingNewInsertion: userActionAllowsPendingNewInsertion
            ),
            expectedOutput: TimelineProjectionExpectedOutput(
                identity: identity,
                resolveExpectations: resolveExpectations,
                layout: layout,
                visibility: visibility,
                fallback: fallback,
                mutation: mutation
            )
        )
    }

    private static func resolve(
        _ target: TimelineDelayedResolveTarget,
        from initialState: TimelineProjectionResolveState,
        to expectedState: TimelineProjectionResolveState
    ) -> TimelineResolveExpectation {
        TimelineResolveExpectation(
            target: target,
            initialState: initialState,
            expectedState: expectedState
        )
    }

    private static func visibility(
        _ mode: TimelineVisibilityMode,
        includedInVisibleSnapshot: Bool = true
    ) -> TimelineVisibilityExpectation {
        TimelineVisibilityExpectation(
            mode: mode,
            includedInVisibleSnapshot: includedInVisibleSnapshot
        )
    }

    private static func fallback(_ mode: TimelineFallbackMode) -> TimelineFallbackExpectation {
        TimelineFallbackExpectation(
            mode: mode,
            keepsSourceNoteVisible: true
        )
    }

    private static func homeLayout(
        reservedMediaAspectRatio: Double? = nil,
        reservedMediaHeight: Double? = nil,
        linkPreviewMode: LinkPreviewMode = .absent,
        quoteMode: QuoteCardMode = .absent,
        replyHeaderMode: ReplyHeaderMode = .absent,
        bodyMentionRendering: MentionRenderingMode = .resolvedDisplayNameWithFallback,
        maxBodyLinesInCollapsedMode: Int? = 8,
        maxQuoteLines: Int = 3
    ) -> TimelineLayoutExpectation {
        TimelineLayoutExpectation(
            contract: TimelineRowLayoutContract(
                rowKind: .home,
                canChangeHeightAfterFirstDisplay: false,
                reservedMediaAspectRatio: reservedMediaAspectRatio,
                reservedMediaHeight: reservedMediaHeight,
                linkPreviewMode: linkPreviewMode,
                quoteMode: quoteMode,
                replyHeaderMode: replyHeaderMode,
                bodyMentionRendering: bodyMentionRendering,
                maxBodyLinesInCollapsedMode: maxBodyLinesInCollapsedMode,
                maxQuoteLines: maxQuoteLines,
                allowsInlineParentPreviewInHome: false
            ),
            noUnlimitedHeightGrowthAfterResolve: true,
            isDetailOnly: false
        )
    }

    private static func eventID(repeating seed: String) -> EventID {
        EventID(hex: String(repeating: seed, count: 64))
    }
}
