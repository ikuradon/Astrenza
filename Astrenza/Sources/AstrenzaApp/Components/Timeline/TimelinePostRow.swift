import SwiftUI

struct TimelinePostRow: View {
    let post: TimelinePost
    let swipeSettings: TimelineSwipeSettings
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia, Int) -> Void
    let onOpenURL: (URL) -> Void
    let onPostActionChoice: (TimelinePost, PostActionChoice) -> Void
    @State private var didHandleActionGesture = false

    var body: some View {
        TimelineSwipeContainer(
            swipeSettings: swipeSettings,
            onSwipeChanged: {},
            onSwipeAction: performSwipeAction
        ) {
            rowContent
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: AstrenzaSpacing.point5) {
            if let repostedBy = post.repostedBy {
                RepostAttributionView(attribution: repostedBy)
                    .padding(.leading, AstrenzaTimelineMetrics.avatarSize - AstrenzaSpacing.point7)
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

                    TimelinePostContentView(
                        post: post,
                        onTap: handleRowTap,
                        onOpenQuotedPost: openEmbeddedPost,
                        onOpenAttachment: openAttachment,
                        onOpenRichURL: handleRichTextURL
                    )

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
        HStack(alignment: .firstTextBaseline, spacing: AstrenzaSpacing.point6) {
            TimelineAuthorHeader(author: post.author, isLocked: post.isLocked)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Spacer(minLength: AstrenzaSpacing.point8)

            if post.replyContext != nil {
                TimelineReplyMarker()
                    .fixedSize()
            }

            RelativeTimestampText(createdAt: post.createdAt)
                .font(.system(size: AstrenzaTimelineMetrics.timestampFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .fixedSize()
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
                menuKind: .repost,
                onMenuSelection: handleActionMenuSelection
            )
            TimelinePostActionButton(
                inactiveSystemName: "star",
                activeSystemName: "star.fill",
                isActive: post.actionState.didFavorite,
                accessibilityLabel: "Favorite",
                accessibilityIdentifier: "timeline.action.favorite.\(post.id)",
                menuKind: .favorite,
                onMenuSelection: handleActionMenuSelection
            )
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
                isActive: false,
                accessibilityLabel: "More actions",
                accessibilityIdentifier: "timeline.action.more.\(post.id)",
                menuKind: .more,
                showsMenuAsPrimaryAction: true,
                onMenuSelection: handleActionMenuSelection
            )
        }
        .padding(.top, AstrenzaSpacing.point2)
    }
}

private extension TimelinePostRow {
    func handleActionMenuSelection(_ selection: TimelinePostActionMenuSelection) {
        switch selection {
        case .more(.viewDetails):
            onOpenPost(post)
        case .more(let choice):
            onPostActionChoice(post, choice)
        case .repost, .favorite:
            break
        }
    }

    func handleRowTap() {
        if didHandleActionGesture {
            didHandleActionGesture = false
            return
        }

        onOpenPost(post)
    }

    func handleAvatarTap() {
        if didHandleActionGesture {
            didHandleActionGesture = false
            return
        }

        onOpenProfile(post)
    }

    func openEmbeddedPost(_ selectedPost: TimelinePost) {
        didHandleActionGesture = true
        onOpenPost(selectedPost)
    }

    func openAttachment(_ media: TimelineMedia, initialTileIndex: Int) {
        didHandleActionGesture = true

        if media.isFullscreenMedia {
            onOpenMedia(media, initialTileIndex)
        } else if let url = media.browserURL {
            onOpenURL(url)
        }
    }

    func handleRichTextURL(_ url: URL) -> OpenURLAction.Result {
        didHandleActionGesture = true

        switch TimelineRichContentRoute(url: url) {
        case .external(let url):
            onOpenURL(url)
            return .handled
        case .profile(let pubkey, _):
            onOpenProfile(profilePost(pubkey: pubkey))
            return .handled
        case .event(let eventID, _, _, _):
            onOpenPost(referencedEventPost(eventID: eventID))
            return .handled
        case .hashtag:
            return .handled
        case .unsupported:
            return .discarded
        }
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
            createdAt: TimelineMockClock.referenceNow,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        )
    }

    func referencedEventPost(eventID: String) -> TimelinePost {
        TimelinePost(
            id: eventID,
            author: .unresolved(pubkey: eventID),
            avatar: AvatarStyle(
                primary: .astrenzaAccent,
                secondary: .astrenzaAttachmentBackground,
                symbolName: "doc.text",
                pictureState: .metadataPending,
                placeholderSeed: eventID
            ),
            body: "",
            createdAt: TimelineMockClock.referenceNow,
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
