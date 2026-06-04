import SwiftUI

struct TimelinePostRow: View {
    let post: TimelinePost
    let isActionMenuPresented: Bool
    let swipeSettings: TimelineSwipeSettings
    let onActionEvent: (TimelinePostActionEvent) -> Void
    let onOpenPost: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia) -> Void
    let onOpenURL: (URL) -> Void
    let onDismissActionMenu: () -> Void
    @State private var didHandleActionGesture = false
    @State private var isActionLongPressActive = false
    @State private var swipeFeedback: TimelineSwipeAction?
    @State private var swipeTranslation: CGFloat = 0

    var body: some View {
        ZStack {
            swipeActionBackdrop
            rowContent
                .offset(x: displayedSwipeOffset)
        }
        .clipped()
        .contentShape(Rectangle())
        .background {
            TimelineRowPanGestureHost(
                isEnabled: !isActionLongPressActive,
                onChanged: handleSwipeChanged,
                onEnded: handleSwipeEnded
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if let swipeFeedback {
                TimelineSwipeFeedbackView(action: swipeFeedback)
                    .padding(.top, 10)
                    .transition(.scale(scale: 0.84).combined(with: .opacity))
            }
        }
    }

    private var displayedSwipeOffset: CGFloat {
        guard abs(swipeTranslation) > 0 else { return 0 }
        let cappedOffset = min(abs(swipeTranslation), 178)
        return cappedOffset * (swipeTranslation < 0 ? -1 : 1)
    }

    private var swipeProgress: Double {
        min(max(abs(swipeTranslation) / TimelineSwipeMetrics.longThreshold, 0.18), 1)
    }

    private var currentSwipeAction: TimelineSwipeAction? {
        guard let classification = swipeClassification(for: swipeTranslation) else { return nil }
        return swipeAction(for: classification)
    }

    @ViewBuilder
    private var swipeActionBackdrop: some View {
        if let action = currentSwipeAction {
            HStack {
                if swipeTranslation > 0 {
                    TimelineSwipeActionIndicator(action: action, alignment: .leading)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    TimelineSwipeActionIndicator(action: action, alignment: .trailing)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(action.backgroundColor.opacity(swipeProgress))
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let repostedBy = post.repostedBy {
                RepostAttributionView(attribution: repostedBy)
                    .padding(.leading, 47)
                    .padding(.trailing, 16)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: handleRowTap)
            }

            HStack(alignment: .top, spacing: 12) {
                AvatarView(style: post.avatar, size: 54)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: handleRowTap)

                VStack(alignment: .leading, spacing: 8) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.astrenzaSeparator)
                .padding(.leading, 82)
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
                .font(.system(size: 16, weight: .semibold, design: .rounded))
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
        VStack(alignment: .leading, spacing: 8) {
            textContent

            attachmentContent
        }
    }

    private var textContent: some View {
        TimelinePostBodyText(text: post.body, mention: post.replyMention)
    }

    private var attachmentContent: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                accessibilityLabel: "Reply"
            )
            TimelinePostActionButton(
                inactiveSystemName: "arrow.triangle.2.circlepath",
                activeSystemName: "arrow.triangle.2.circlepath",
                isActive: post.actionState.didRepost,
                accessibilityLabel: "Repost",
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
            .floatingActionAnchor(postID: post.id, kind: .repost)
            TimelinePostActionButton(
                inactiveSystemName: "star",
                activeSystemName: "star.fill",
                isActive: post.actionState.didFavorite,
                accessibilityLabel: "Favorite",
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
            .floatingActionAnchor(postID: post.id, kind: .favorite)
            TimelinePostActionButton(
                inactiveSystemName: "bolt",
                activeSystemName: "bolt.fill",
                isActive: post.actionState.didZap,
                accessibilityLabel: "Zap"
            )
            TimelinePostActionButton(
                inactiveSystemName: "gearshape",
                activeSystemName: "gearshape.fill",
                isActive: isActionMenuPresented,
                accessibilityLabel: "More actions",
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
            .floatingActionAnchor(postID: post.id, kind: .more)
        }
        .padding(.top, 4)
    }

    private func sendActionEvent(_ kind: TimelinePostActionKind, phase: TimelinePostActionPhase) {
        didHandleActionGesture = true
        onActionEvent(TimelinePostActionEvent(postID: post.id, kind: kind, phase: phase))
    }

    private func handleRowTap() {
        if didHandleActionGesture {
            didHandleActionGesture = false
            return
        }

        onDismissActionMenu()
        onOpenPost(post)
    }

    private func openEmbeddedPost(_ selectedPost: TimelinePost) {
        didHandleActionGesture = true
        onDismissActionMenu()
        onOpenPost(selectedPost)
    }

    private func openAttachment(_ media: TimelineMedia) {
        didHandleActionGesture = true
        onDismissActionMenu()

        if media.isFullscreenMedia {
            onOpenMedia(media)
        } else if let url = media.browserURL {
            onOpenURL(url)
        }
    }

    private func handleSwipeChanged(_ translationWidth: CGFloat) {
        onDismissActionMenu()
        swipeTranslation = translationWidth
    }

    private func handleSwipeEnded(_ translationWidth: CGFloat) {
        defer {
            withAnimation(.spring(duration: 0.2, bounce: 0.1)) {
                swipeTranslation = 0
            }
        }

        guard let classification = swipeClassification(for: translationWidth) else {
            return
        }

        performSwipeAction(swipeAction(for: classification))
    }

    private func swipeClassification(for translationWidth: CGFloat) -> TimelineSwipeClassification? {
        let distance = abs(translationWidth)
        guard distance >= TimelineSwipeMetrics.shortThreshold else { return nil }

        let direction: TimelineSwipeDirection = translationWidth < 0 ? .left : .right
        let length: TimelineSwipeLength = distance >= TimelineSwipeMetrics.longThreshold ? .long : .short
        return TimelineSwipeClassification(direction: direction, length: length)
    }

    private func swipeAction(for classification: TimelineSwipeClassification) -> TimelineSwipeAction {
        let title: String
        switch (classification.direction, classification.length) {
        case (.left, .long):
            title = swipeSettings.longLeftSwipe
        case (.right, .long):
            title = swipeSettings.longRightSwipe
        case (.left, .short):
            title = swipeSettings.shortLeftSwipe
        case (.right, .short):
            title = swipeSettings.shortRightSwipe
        }

        return TimelineSwipeAction(title: title)
    }

    private func performSwipeAction(_ action: TimelineSwipeAction) {
        guard action.kind != .noAction else {
            showSwipeFeedback(action)
            return
        }

        onDismissActionMenu()

        switch action.kind {
        case .viewDetail:
            onOpenPost(post)
        case .reply:
            onReplyPost(post)
        case .favorite, .repost, .quote, .bookmark, .openLink, .copyLink, .copyPost, .sharePost, .readLater, .translate:
            showSwipeFeedback(action)
        case .noAction:
            break
        }
    }

    private func showSwipeFeedback(_ action: TimelineSwipeAction) {
        withAnimation(.spring(duration: 0.24, bounce: 0.16)) {
            swipeFeedback = action
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeOut(duration: 0.18)) {
                if swipeFeedback == action {
                    swipeFeedback = nil
                }
            }
        }
    }
}
