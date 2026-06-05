import SwiftUI

struct PostDetailView: View {
    let post: TimelinePost
    let swipeSettings: TimelineSwipeSettings
    let onOpenPost: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia) -> Void
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

                        TimelinePostBodyText(text: post.body, mention: post.replyMention, fontSize: 22)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let linkSummary = post.linkSummary {
                            DetailLinkSummaryView(summary: linkSummary)
                        }

                        if let quotedPost = post.quotedPost {
                            Button {
                                onOpenPost(quotedPost.timelinePost())
                            } label: {
                                QuotedPostCard(quotedPost: quotedPost)
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
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.astrenzaBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private var replyAncestorPosts: [TimelinePost] {
        MockTimelineData.replyAncestors(for: post)
    }

    private var showsReplyParentIndicator: Bool {
        !replyAncestorPosts.isEmpty && !isReplyAncestorStackVisible
    }

    private func openAttachment(_ media: TimelineMedia) {
        if media.isFullscreenMedia {
            onOpenMedia(media)
        } else if let url = media.browserURL {
            onOpenURL(url)
        }
    }

    private var postHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            AvatarView(style: post.avatar, size: 68)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(post.author.primaryText)
                        .font(.system(size: 23, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if post.contentWarning != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Sensitive post")
                    }
                }

                Text(post.author.secondaryText)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.astrenzaAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
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
            ForEach(MockTimelineData.detailReplies(for: post)) { reply in
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
        let baseDate = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "Asia/Tokyo"),
            year: 2026,
            month: 6,
            day: 4,
            hour: 20,
            minute: 20
        ).date ?? Date()

        let elapsedSeconds = timestamp.elapsedSecondsFromRelativeTimestamp
        let date = baseDate.addingTimeInterval(-elapsedSeconds)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/MM/dd HH:mm 'JST'"
        return formatter.string(from: date)
    }
}

private extension String {
    var elapsedSecondsFromRelativeTimestamp: TimeInterval {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let unit = trimmed.last,
              let value = Double(trimmed.dropLast())
        else {
            return 0
        }

        switch unit {
        case "m":
            return value * 60
        case "h":
            return value * 60 * 60
        default:
            return 0
        }
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
