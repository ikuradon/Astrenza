import SwiftUI

struct TimelinePostRow: View {
    let post: TimelinePost
    let isActionMenuPresented: Bool
    let swipeSettings: TimelineSwipeSettings
    let onActionEvent: (TimelinePostActionEvent) -> Void
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia) -> Void
    let onOpenURL: (URL) -> Void
    let onDismissActionMenu: () -> Void
    private var needsFloatingActionAnchors: Bool {
        isActionMenuPresented || isActionLongPressActive
    }
    @State private var didHandleActionGesture = false
    @State private var isActionLongPressActive = false

    var body: some View {
        TimelineSwipeContainer(
            swipeSettings: swipeSettings,
            isEnabled: !isActionLongPressActive,
            onSwipeChanged: onDismissActionMenu,
            onSwipeAction: performSwipeAction
        ) {
            rowContent
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let repostedBy = post.repostedBy {
                RepostAttributionView(attribution: repostedBy)
                    .padding(.leading, AstrenzaTimelineMetrics.avatarSize - 7)
                    .padding(.trailing, AstrenzaTimelineMetrics.rowHorizontalPadding)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: handleRowTap)
            }

            HStack(alignment: .top, spacing: AstrenzaTimelineMetrics.rowAvatarSpacing) {
                AvatarView(style: post.avatar, size: AstrenzaTimelineMetrics.avatarSize)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: handleAvatarTap)
                    .accessibilityIdentifier("timeline.avatar.\(post.id)")

                VStack(alignment: .leading, spacing: AstrenzaTimelineMetrics.rowContentSpacing) {
                    if let replyContext = post.replyContext {
                        TimelineReplyContextView(context: replyContext, style: .timeline)
                            .padding(.bottom, -2)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: handleRowTap)
                    }

                    header
                        .contentShape(Rectangle())
                        .onTapGesture(perform: handleRowTap)

                    sensitiveAwareContent

                    actionRow
                }
            }
        }
        .padding(.horizontal, AstrenzaTimelineMetrics.rowHorizontalPadding)
        .padding(.vertical, AstrenzaTimelineMetrics.rowVerticalPadding)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.astrenzaSeparator)
                .padding(.leading, AstrenzaTimelineMetrics.rowHorizontalPadding + AstrenzaTimelineMetrics.avatarSize + AstrenzaTimelineMetrics.rowAvatarSpacing)
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TimelineAuthorHeader(author: post.author, isLocked: post.isLocked)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if post.replyContext != nil {
                TimelineReplyMarker()
                    .fixedSize()
            }

            Text(post.timestamp)
                .font(.system(size: AstrenzaTimelineMetrics.timestampFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var sensitiveAwareContent: some View {
        if let contentWarning = post.contentWarning {
            SensitiveTimelineContent(contentWarning: contentWarning) {
                postContent
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: handleRowTap)
        } else {
            postContent
        }
    }

    private var postContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            textContent

            bodySummaryContent

            attachmentContent
        }
    }

    @ViewBuilder
    private var textContent: some View {
        let bodyText = TimelinePostBodyText(
            text: post.body,
            richContent: post.richBody,
            mention: post.replyMention,
            lineLimit: post.bodyPresentation.timelineLineLimit
        )
            .contentShape(Rectangle())
            .accessibilityIdentifier("timeline.body.\(post.id)")

        if post.richBody != nil {
            bodyText
                .environment(\.openURL, OpenURLAction(handler: handleRichTextURL))
                .onTapGesture(perform: handleRowTap)
        } else {
            bodyText
                .onTapGesture(perform: handleRowTap)
        }
    }

    @ViewBuilder
    private var bodySummaryContent: some View {
        if post.bodyPresentation.collapseReason != nil || post.linkSummary != nil {
            HStack(spacing: 7) {
                if let collapseReason = post.bodyPresentation.collapseReason {
                    TimelineBodySummaryPill(
                        systemName: collapseReason.systemName,
                        text: collapseReason.label,
                        prominence: collapseReason == .lowTrustLinks || collapseReason == .filtered ? .warning : .normal
                    )
                }

                if let linkSummary = post.linkSummary {
                    TimelineBodySummaryPill(
                        systemName: "link",
                        text: linkSummary.compactText,
                        prominence: linkSummary.unresolvedCount > 0 ? .muted : .normal
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: handleRowTap)
        }
    }

    private var attachmentContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quotedPost = post.quotedPost {
                Button {
                    openEmbeddedPost(quotedPost.timelinePost())
                } label: {
                    QuotedPostCard(quotedPost: quotedPost)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open quoted post by \(quotedPost.author.primaryText)")
                .accessibilityAction {
                    openEmbeddedPost(quotedPost.timelinePost())
                }
            }

            if let media = post.media {
                TimelineAttachmentButton(
                    media: media,
                    isProtected: post.shouldObscureExternalAttachments,
                    accessibilityLabel: "Open attachment for post by \(post.author.primaryText)",
                    onOpen: openAttachment
                )
                .padding(.top, 2)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 0) {
            TimelinePostActionButton(
                inactiveSystemName: "bubble.left",
                activeSystemName: "bubble.left.fill",
                isActive: post.actionState.didReply,
                accessibilityLabel: "Reply",
                accessibilityIdentifier: "timeline.action.reply.\(post.id)"
            )
            TimelinePostActionButton(
                inactiveSystemName: "arrow.triangle.2.circlepath",
                activeSystemName: "arrow.triangle.2.circlepath",
                isActive: post.actionState.didRepost,
                accessibilityLabel: "Repost",
                accessibilityIdentifier: "timeline.action.repost.\(post.id)",
                supportsLongPressDrag: true,
                action: {
                    sendActionEvent(.repost, phase: .tap)
                },
                onLongPress: {
                    isActionLongPressActive = true
                    sendActionEvent(.repost, phase: .longPressBegan)
                },
                onLongPressDragChanged: { location in
                    sendActionEvent(.repost, phase: .dragChanged(location))
                },
                onLongPressDragEnded: { location in
                    isActionLongPressActive = false
                    sendActionEvent(.repost, phase: .dragEnded(location))
                }
            )
            .floatingActionAnchor(postID: post.id, kind: .repost, isEnabled: needsFloatingActionAnchors)
            TimelinePostActionButton(
                inactiveSystemName: "star",
                activeSystemName: "star.fill",
                isActive: post.actionState.didFavorite,
                accessibilityLabel: "Favorite",
                accessibilityIdentifier: "timeline.action.favorite.\(post.id)",
                supportsLongPressDrag: true,
                action: {
                    sendActionEvent(.favorite, phase: .tap)
                },
                onLongPress: {
                    isActionLongPressActive = true
                    sendActionEvent(.favorite, phase: .longPressBegan)
                },
                onLongPressDragChanged: { location in
                    sendActionEvent(.favorite, phase: .dragChanged(location))
                },
                onLongPressDragEnded: { location in
                    isActionLongPressActive = false
                    sendActionEvent(.favorite, phase: .dragEnded(location))
                }
            )
            .floatingActionAnchor(postID: post.id, kind: .favorite, isEnabled: needsFloatingActionAnchors)
            TimelinePostActionButton(
                inactiveSystemName: "bolt",
                activeSystemName: "bolt.fill",
                isActive: post.actionState.didZap,
                accessibilityLabel: "Zap",
                accessibilityIdentifier: "timeline.action.zap.\(post.id)"
            )
            TimelinePostActionButton(
                inactiveSystemName: "gearshape",
                activeSystemName: "gearshape.fill",
                isActive: isActionMenuPresented,
                accessibilityLabel: "More actions",
                accessibilityIdentifier: "timeline.action.more.\(post.id)",
                supportsLongPressDrag: true,
                action: {
                    sendActionEvent(.more, phase: .tap)
                },
                onLongPress: {
                    isActionLongPressActive = true
                    sendActionEvent(.more, phase: .longPressBegan)
                },
                onLongPressDragChanged: { location in
                    sendActionEvent(.more, phase: .dragChanged(location))
                },
                onLongPressDragEnded: { location in
                    isActionLongPressActive = false
                    sendActionEvent(.more, phase: .dragEnded(location))
                }
            )
            .floatingActionAnchor(postID: post.id, kind: .more, isEnabled: needsFloatingActionAnchors)
        }
        .padding(.top, 2)
    }
}

private extension TimelinePostRow {
    func sendActionEvent(_ kind: TimelinePostActionKind, phase: TimelinePostActionPhase) {
        didHandleActionGesture = true
        onActionEvent(TimelinePostActionEvent(postID: post.id, kind: kind, phase: phase))
    }

    func handleRowTap() {
        if didHandleActionGesture {
            didHandleActionGesture = false
            return
        }

        onDismissActionMenu()
        onOpenPost(post)
    }

    func handleAvatarTap() {
        if didHandleActionGesture {
            didHandleActionGesture = false
            return
        }

        onDismissActionMenu()
        onOpenProfile(post)
    }

    func openEmbeddedPost(_ selectedPost: TimelinePost) {
        didHandleActionGesture = true
        onDismissActionMenu()
        onOpenPost(selectedPost)
    }

    func openAttachment(_ media: TimelineMedia) {
        didHandleActionGesture = true
        onDismissActionMenu()

        if media.isFullscreenMedia {
            onOpenMedia(media)
        } else if let url = media.browserURL {
            onOpenURL(url)
        }
    }

    func handleRichTextURL(_ url: URL) -> OpenURLAction.Result {
        didHandleActionGesture = true

        guard url.scheme == "astrenza" else {
            onOpenURL(url)
            return .handled
        }

        if url.host == "profile", let pubkey = url.pathComponents.dropFirst().first {
            onOpenProfile(profilePost(pubkey: pubkey))
            return .handled
        }

        if url.host == "event" {
            onOpenPost(post)
            return .handled
        }

        if url.host == "hashtag" {
            return .handled
        }

        return .discarded
    }

    func profilePost(pubkey: String) -> TimelinePost {
        TimelinePost(
            author: .unresolved(pubkey: pubkey),
            avatar: AvatarStyle(
                primary: .astrenzaAccent,
                secondary: .astrenzaAttachmentBackground,
                symbolName: "person.fill",
                pictureState: .metadataPending,
                placeholderSeed: pubkey
            ),
            body: "",
            timestamp: "",
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        )
    }

    func performSwipeAction(_ action: TimelineSwipeAction) -> Bool {
        guard action.kind != .noAction else {
            return true
        }

        onDismissActionMenu()

        switch action.kind {
        case .viewDetail:
            onOpenPost(post)
            return false
        case .reply:
            onReplyPost(post)
            return false
        case .favorite, .repost, .quote, .bookmark, .openLink, .copyLink, .copyPost, .sharePost, .readLater, .translate:
            return true
        case .noAction:
            return true
        }
    }
}
