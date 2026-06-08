import SwiftUI

struct TimelinePostContentView: View {
    let post: TimelinePost
    let onTap: () -> Void
    let onOpenQuotedPost: (TimelinePost) -> Void
    let onOpenAttachment: (TimelineMedia, Int) -> Void
    let onOpenRichURL: (URL) -> OpenURLAction.Result

    var body: some View {
        if let contentWarning = post.contentWarning {
            SensitiveTimelineContent(contentWarning: contentWarning) {
                postContent
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
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
                .environment(\.openURL, OpenURLAction(handler: onOpenRichURL))
                .onTapGesture(perform: onTap)
        } else {
            bodyText
                .onTapGesture(perform: onTap)
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
            .onTapGesture(perform: onTap)
        }
    }

    private var attachmentContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quotedPost = post.quotedPost {
                Button {
                    onOpenQuotedPost(quotedPost.timelinePost())
                } label: {
                    QuotedPostCard(quotedPost: quotedPost, onOpenRichURL: onOpenRichURL)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open quoted post by \(quotedPost.author.primaryText)")
                .accessibilityAction {
                    onOpenQuotedPost(quotedPost.timelinePost())
                }
            }

            if let media = post.media {
                TimelineAttachmentButton(
                    media: media,
                    isProtected: post.shouldObscureExternalAttachments,
                    accessibilityLabel: "Open attachment for post by \(post.author.primaryText)",
                    onOpen: onOpenAttachment
                )
                .padding(.top, 2)
            }
        }
    }
}
