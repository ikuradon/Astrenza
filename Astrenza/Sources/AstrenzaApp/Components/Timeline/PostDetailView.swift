import SwiftUI

struct PostDetailView: View {
    let post: TimelinePost
    let replyAncestors: [TimelinePost]
    let replies: [TimelinePost]
    let swipeSettings: TimelineSwipeSettings
    let onOpenPost: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia, Int) -> Void
    let onOpenURL: (URL) -> Void
    @State private var isReplyAncestorStackVisible = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if !replyAncestorPosts.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(replyAncestorPosts) { ancestorPost in
                                detailThreadRow(ancestorPost)
                            }
                        }
                        .onScrollVisibilityChange(threshold: 0.05) { isVisible in
                            isReplyAncestorStackVisible = isVisible
                        }
                    }

                    postHeader
                        .id(DetailScrollAnchor.currentPost)

                    VStack(alignment: .leading, spacing: 18) {
                        if let contentWarning = post.contentWarning {
                            SensitiveDetailBanner(contentWarning: contentWarning)
                        }

                        TimelinePostBodyText(
                            text: post.body,
                            richContent: post.richBody,
                            mention: post.replyMention
                        )
                        .environment(\.openURL, OpenURLAction(handler: handleRichTextURL))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let linkSummary = post.linkSummary {
                            DetailLinkSummaryView(summary: linkSummary)
                        }

                        if let quotedPost = post.quotedPost {
                            Button {
                                onOpenPost(quotedPost.timelinePost())
                            } label: {
                                QuotedPostCard(quotedPost: quotedPost, onOpenRichURL: handleRichTextURL)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open quoted post by \(quotedPost.author.primaryText)")
                        }

                        if let media = post.media {
                            TimelineAttachmentButton(
                                media: media,
                                isProtected: post.shouldObscureExternalAttachments,
                                accessibilityLabel: "Open attachment for post by \(post.author.primaryText)",
                                onOpen: openAttachment
                            )
                        }

                        detailActionRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                    detailStats
                    detailMetadata
                    detailReplies

                    Spacer(minLength: 240)
                }
            }
            .onAppear {
                guard !replyAncestorPosts.isEmpty else { return }
                proxy.scrollTo(DetailScrollAnchor.currentPost, anchor: .top)
            }
        }
        .background(Color.astrenzaBackground)
        .accessibilityIdentifier("post.detail")
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.astrenzaBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var replyAncestorPosts: [TimelinePost] {
        replyAncestors
    }

    private var showsReplyParentIndicator: Bool {
        !replyAncestorPosts.isEmpty && !isReplyAncestorStackVisible
    }

    private func openAttachment(_ media: TimelineMedia, initialTileIndex: Int) {
        if media.isFullscreenMedia {
            onOpenMedia(media, initialTileIndex)
        } else if let url = media.browserURL {
            onOpenURL(url)
        }
    }

    private func handleRichTextURL(_ url: URL) -> OpenURLAction.Result {
        switch TimelineRichContentRoute(url: url) {
        case .external(let url):
            onOpenURL(url)
            return .handled
        case .profile(let pubkey, _):
            onOpenPost(profilePost(pubkey: pubkey))
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

    private func profilePost(pubkey: String) -> TimelinePost {
        TimelinePost(
            id: "profile-\(pubkey)",
            author: .unresolved(pubkey: pubkey),
            avatar: AvatarStyle(
                primary: .purple,
                secondary: .blue,
                symbolName: "person.crop.circle.fill",
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

    private func referencedEventPost(eventID: String) -> TimelinePost {
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

    private var postHeader: some View {
        HStack(alignment: .top, spacing: AstrenzaTimelineMetrics.rowAvatarSpacing) {
            AvatarView(style: post.avatar, size: AstrenzaTimelineMetrics.avatarSize)

            HStack(alignment: .top, spacing: 6) {
                TimelineAuthorHeader(author: post.author, isLocked: post.isLocked)

                if post.contentWarning != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Sensitive post")
                        .padding(.top, 1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsReplyParentIndicator {
                ReplyParentIndicator()
                    .padding(.top, 2)
                    .transition(.scale(scale: 0.82, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.24, bounce: 0.12), value: showsReplyParentIndicator)
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 16)
    }

    private var detailActionRow: some View {
        HStack(spacing: 0) {
            detailActionButton("bubble.left")
            detailActionButton("arrow.triangle.2.circlepath")
            detailActionButton("star")
            detailActionButton("square.and.arrow.up")
            detailActionButton("gearshape")
        }
        .padding(.top, 4)
    }

    private func detailActionButton(_ systemName: String) -> some View {
        Button {
        } label: {
            Image(systemName: systemName)
                .font(.system(size: AstrenzaTimelineMetrics.detailActionIconSize, weight: .semibold))
                .foregroundStyle(Color.astrenzaAccent)
                .frame(maxWidth: .infinity)
                .frame(height: AstrenzaTimelineMetrics.detailActionHeight)
        }
        .buttonStyle(.plain)
    }

    private var detailStats: some View {
        HStack(spacing: 0) {
            DetailMetricCell(value: post.boostCount ?? 0, title: "Reposts", showsDivider: true)
            DetailMetricCell(value: post.favoriteCount ?? 0, title: "Reactions")
        }
        .frame(height: 56)
        .background(Color.white.opacity(0.045))
        .overlay(alignment: .top) {
            Divider().overlay(Color.astrenzaSeparator)
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.astrenzaSeparator)
        }
    }

    private var detailMetadata: some View {
        HStack {
            DetailMetadataCell(systemName: "calendar", text: post.detailAbsoluteTimestampText)
        }
        .frame(height: 52)
        .background(Color.white.opacity(0.045))
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.astrenzaSeparator)
        }
    }

    private var detailReplies: some View {
        VStack(spacing: 0) {
            ForEach(replies) { reply in
                detailThreadRow(reply)
            }
        }
    }

    private func detailThreadRow(_ threadPost: TimelinePost) -> some View {
        TimelinePostRow(
            post: threadPost,
            isActionMenuPresented: false,
            swipeSettings: swipeSettings,
            onActionEvent: { _ in },
            onOpenPost: onOpenPost,
            onOpenProfile: { _ in },
            onReplyPost: onReplyPost,
            onOpenMedia: onOpenMedia,
            onOpenURL: onOpenURL,
            onDismissActionMenu: {}
        )
    }
}

private enum DetailScrollAnchor {
    case currentPost
}

private extension TimelinePost {
    var detailAbsoluteTimestampText: String {
        TimelineTimestampFormatter.absoluteText(from: createdAt)
    }
}

private struct SensitiveDetailBanner: View {
    let contentWarning: TimelineContentWarning

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.orange)

                Text("Sensitive Content")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text("NIP-36")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(contentWarning.displayReason)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct DetailLinkSummaryView: View {
    let summary: TimelineLinkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .black))

                Text(summary.compactText)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))

                if summary.unresolvedCount > 0 {
                    Text("\(summary.unresolvedCount) unresolved")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }
            .foregroundStyle(Color.astrenzaAccent)

            Text(summary.detailText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.astrenzaAttachmentBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct DetailMetricCell: View {
    let value: Int
    let title: String
    var showsDivider = false

    var body: some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if showsDivider {
                Divider().overlay(Color.astrenzaSeparator)
            }
        }
    }
}

private struct DetailMetadataCell: View {
    let systemName: String
    let text: String
    var showsDivider = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
            Text(text)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if showsDivider {
                Divider().overlay(Color.astrenzaSeparator)
            }
        }
    }
}

private struct ReplyParentIndicator: View {
    var body: some View {
        HStack(spacing: -3) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 17, weight: .black))
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .black))
                .offset(y: -4)
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("Reply parent above")
    }
}
