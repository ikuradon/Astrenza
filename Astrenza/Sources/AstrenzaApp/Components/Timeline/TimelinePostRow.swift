import SwiftUI
import UIKit

enum FloatingMenuMetrics {
    static let actionWidth: CGFloat = 184
    static let choiceWidth: CGFloat = 188
    static let verticalPadding: CGFloat = 6
    static let actionRowHeight: CGFloat = 34
    static let choiceRowHeight: CGFloat = 40
    static let dividerHeight: CGFloat = 5

    static let actionMenuSize = CGSize(
        width: actionWidth,
        height: verticalPadding * 2 + actionRowHeight * CGFloat(PostActionChoice.allCases.count) + dividerHeight * 3
    )
    static let repostMenuSize = CGSize(
        width: choiceWidth,
        height: verticalPadding * 2 + choiceRowHeight * CGFloat(RepostChoice.allCases.count)
    )
    static let favoriteMenuSize = CGSize(
        width: choiceWidth,
        height: verticalPadding * 2 + choiceRowHeight * CGFloat(FavoriteChoice.allCases.count)
    )
}

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

    private var swipeProgress: Double {
        min(max(abs(swipeTranslation) / TimelineSwipeMetrics.longThreshold, 0.18), 1)
    }

    private var currentSwipeAction: TimelineSwipeAction? {
        guard let classification = swipeClassification(for: swipeTranslation) else { return nil }
        return swipeAction(for: classification)
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

private struct TimelineRowPanGestureHost: UIViewRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.isUserInteractionEnabled = false
        view.onMovedToWindow = { markerView in
            context.coordinator.attachIfNeeded(from: markerView)
        }
        return view
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.markerView = uiView
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TimelineRowPanGestureHost
        weak var markerView: UIView?
        private weak var scrollView: UIScrollView?
        private var recognizer: UIPanGestureRecognizer?
        private var beganInsideRow = false

        init(parent: TimelineRowPanGestureHost) {
            self.parent = parent
        }

        deinit {
            if let recognizer, let scrollView {
                DispatchQueue.main.async {
                    scrollView.removeGestureRecognizer(recognizer)
                }
            }
        }

        func attachIfNeeded(from markerView: UIView) {
            self.markerView = markerView
            guard let targetScrollView = markerView.enclosingScrollView() else { return }
            guard scrollView !== targetScrollView else { return }

            if let recognizer, let scrollView {
                scrollView.removeGestureRecognizer(recognizer)
            }

            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.minimumNumberOfTouches = 1
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            targetScrollView.addGestureRecognizer(recognizer)

            self.scrollView = targetScrollView
            self.recognizer = recognizer
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard parent.isEnabled, beganInsideRow else { return }
            let translation = recognizer.translation(in: scrollView).x

            switch recognizer.state {
            case .began, .changed:
                parent.onChanged(translation)
            case .ended:
                parent.onEnded(translation)
                beganInsideRow = false
            case .cancelled, .failed:
                parent.onEnded(0)
                beganInsideRow = false
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isEnabled,
                  let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer,
                  let markerView,
                  let scrollView
            else {
                return false
            }

            let locationInRow = panRecognizer.location(in: markerView)
            guard markerView.bounds.contains(locationInRow) else {
                beganInsideRow = false
                return false
            }

            let velocity = panRecognizer.velocity(in: scrollView)
            let horizontalSpeed = abs(velocity.x)
            let verticalSpeed = abs(velocity.y)
            beganInsideRow = horizontalSpeed > 120 && horizontalSpeed > verticalSpeed * 1.35
            return beganInsideRow
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }

    final class MarkerView: UIView {
        var onMovedToWindow: ((MarkerView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMovedToWindow?(self)
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var currentView = superview
        while let view = currentView {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            currentView = view.superview
        }
        return nil
    }
}

private struct SensitiveTimelineContent<Content: View>: View {
    let contentWarning: TimelineContentWarning
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            content()
                .blur(radius: 10, opaque: false)
                .saturation(0.55)
                .opacity(0.62)

            SensitiveTimelineOverlay(contentWarning: contentWarning)
        }
        .frame(height: 118)
        .clipped()
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SensitiveTimelineOverlay: View {
    let contentWarning: TimelineContentWarning

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .black))
                Text("CONTENT WARNING")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color.secondary.opacity(0.92), in: Capsule())

            Text(contentWarning.displayReason)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("Tap to open detail")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.astrenzaAccent)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.astrenzaBackground.opacity(0.18))
    }
}

private enum TimelineSwipeMetrics {
    static let shortThreshold: CGFloat = 58
    static let longThreshold: CGFloat = 146
}

private enum TimelineSwipeDirection {
    case left
    case right
}

private enum TimelineSwipeLength {
    case short
    case long
}

private struct TimelineSwipeClassification {
    let direction: TimelineSwipeDirection
    let length: TimelineSwipeLength
}

private struct TimelineSwipeAction: Equatable {
    let title: String

    var kind: Kind {
        switch title {
        case "Favorite":
            .favorite
        case "Repost", "Boost":
            .repost
        case "Quote":
            .quote
        case "Bookmark":
            .bookmark
        case "Open Link to Post":
            .openLink
        case "Copy Link to Post":
            .copyLink
        case "Copy Post":
            .copyPost
        case "Share Post":
            .sharePost
        case "Add to Read Later":
            .readLater
        case "Translate":
            .translate
        case "Reply":
            .reply
        case "View Detail":
            .viewDetail
        default:
            .noAction
        }
    }

    var systemName: String {
        switch kind {
        case .favorite:
            "star.fill"
        case .repost:
            "arrow.triangle.2.circlepath"
        case .quote:
            "quote.bubble.fill"
        case .bookmark:
            "bookmark.fill"
        case .openLink:
            "safari.fill"
        case .copyLink:
            "link"
        case .copyPost:
            "doc.on.doc.fill"
        case .sharePost:
            "square.and.arrow.up.fill"
        case .readLater:
            "clock.fill"
        case .translate:
            "character.bubble.fill"
        case .reply:
            "bubble.left.fill"
        case .viewDetail:
            "info.circle.fill"
        case .noAction:
            "xmark"
        }
    }

    var backgroundColor: Color {
        switch kind {
        case .favorite:
            .yellow
        case .repost:
            .green
        case .quote, .reply, .openLink:
            .blue
        case .bookmark, .readLater:
            .orange
        case .copyLink, .copyPost, .sharePost:
            .cyan
        case .translate:
            .purple
        case .viewDetail:
            Color.astrenzaAccent
        case .noAction:
            .gray
        }
    }

    enum Kind {
        case favorite
        case repost
        case quote
        case bookmark
        case openLink
        case copyLink
        case copyPost
        case sharePost
        case readLater
        case translate
        case reply
        case viewDetail
        case noAction
    }
}

private struct TimelineSwipeActionIndicator: View {
    let action: TimelineSwipeAction
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Image(systemName: action.systemName)
                .font(.system(size: 24, weight: .black))
            Text(action.title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(.white)
        .frame(width: 104, alignment: alignment == .leading ? .leading : .trailing)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

private struct TimelineSwipeFeedbackView: View {
    let action: TimelineSwipeAction

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: action.systemName)
            Text(action.title)
        }
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(action.backgroundColor.opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
    }
}

private struct RepostAttributionView: View {
    let attribution: TimelineRepostAttribution

    var body: some View {
        HStack(spacing: 7) {
            AvatarView(style: attribution.avatar, size: 24)

            Text(attribution.author.primaryText)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .black))

            Text(attribution.timestamp)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.07), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TimelineAuthorHeader: View {
    let author: TimelineAuthor
    let isLocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(author.primaryText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.88)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                Image(systemName: author.secondarySystemName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(secondaryIconStyle)
                    .frame(width: 13)

                Text(author.secondaryText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var secondaryIconStyle: AnyShapeStyle {
        switch author.nip05Status {
        case .valid:
            AnyShapeStyle(Color.green)
        case .invalid:
            AnyShapeStyle(Color.orange)
        case .unchecked:
            AnyShapeStyle(Color.secondary)
        case .absent:
            AnyShapeStyle(.tertiary)
        }
    }
}

private struct QuotedPostCard: View {
    let quotedPost: QuotedTimelinePost

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            AvatarView(style: quotedPost.avatar, size: 32)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(quotedPost.author.primaryText)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(quotedPost.author.secondaryText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    Text(quotedPost.timestamp)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }

                if quotedPost.isAvailable {
                    Text(quotedPost.body)
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(2)
                        .foregroundStyle(Color.astrenzaText)
                        .lineLimit(3)
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 13, weight: .bold))
                        Text("Quoted note could not be loaded")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.astrenzaAttachmentBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

enum TimelinePostActionKind: Hashable {
    case repost
    case favorite
    case more
}

enum TimelinePostActionPhase {
    case tap
    case longPressBegan
    case dragChanged(CGPoint)
    case dragEnded(CGPoint?)
}

struct TimelinePostActionEvent {
    let postID: TimelinePost.ID
    let kind: TimelinePostActionKind
    let phase: TimelinePostActionPhase
}

struct TimelinePostActionAnchorID: Hashable {
    let postID: TimelinePost.ID
    let kind: TimelinePostActionKind
}

protocol FloatingChoiceItem: CaseIterable, Equatable, Hashable {
    var title: String { get }
    var systemName: String { get }
}

enum PostActionChoice: FloatingChoiceItem {
    case report
    case mute
    case translate
    case bookmark
    case copyLink
    case shareLink
    case viewDetails

    var title: String {
        switch self {
        case .report:
            "Report"
        case .mute:
            "Mute"
        case .translate:
            "Translate"
        case .bookmark:
            "Bookmark"
        case .copyLink:
            "Copy Link"
        case .shareLink:
            "Share Link"
        case .viewDetails:
            "View Details"
        }
    }

    var systemName: String {
        switch self {
        case .report:
            "exclamationmark.bubble"
        case .mute:
            "speaker.slash"
        case .translate:
            "character.bubble"
        case .bookmark:
            "bookmark"
        case .copyLink:
            "link"
        case .shareLink:
            "square.and.arrow.up"
        case .viewDetails:
            "info.circle"
        }
    }

    var followsDivider: Bool {
        switch self {
        case .mute, .bookmark, .shareLink:
            true
        case .report, .translate, .copyLink, .viewDetails:
            false
        }
    }
}

enum RepostChoice: FloatingChoiceItem {
    case repost
    case quotedRepost

    var title: String {
        switch self {
        case .repost:
            "Repost"
        case .quotedRepost:
            "Quoted Repost"
        }
    }

    var systemName: String {
        switch self {
        case .repost:
            "arrow.triangle.2.circlepath"
        case .quotedRepost:
            "quote.bubble"
        }
    }
}

enum FavoriteChoice: FloatingChoiceItem {
    case favorite
    case customReaction
    case bookmark

    var title: String {
        switch self {
        case .favorite:
            "Favorite"
        case .customReaction:
            "Custom Reaction"
        case .bookmark:
            "Bookmark"
        }
    }

    var systemName: String {
        switch self {
        case .favorite:
            "star"
        case .customReaction:
            "face.smiling"
        case .bookmark:
            "bookmark"
        }
    }
}

struct TimelinePostActionAnchorKey: PreferenceKey {
    static let defaultValue: [TimelinePostActionAnchorID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TimelinePostActionAnchorID: Anchor<CGRect>],
        nextValue: () -> [TimelinePostActionAnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func floatingActionAnchor(postID: TimelinePost.ID, kind: TimelinePostActionKind) -> some View {
        anchorPreference(key: TimelinePostActionAnchorKey.self, value: .bounds) {
            [TimelinePostActionAnchorID(postID: postID, kind: kind): $0]
        }
    }
}

struct PostActionMenu: View {
    let selectedChoice: PostActionChoice?
    let onSelect: (PostActionChoice) -> Void

    var body: some View {
        FloatingMenuSurface(width: FloatingMenuMetrics.actionWidth, accessibilityLabel: "Post actions") {
            ForEach(Array(PostActionChoice.allCases), id: \.self) { choice in
                FloatingMenuRow(
                    title: choice.title,
                    systemName: choice.systemName,
                    height: FloatingMenuMetrics.actionRowHeight,
                    isSelected: selectedChoice == choice,
                    action: {
                        onSelect(choice)
                    }
                )

                if choice.followsDivider {
                    PostActionMenuDivider()
                }
            }
        }
    }
}

struct RepostChoiceMenu: View {
    let selectedChoice: RepostChoice?
    let onSelect: () -> Void

    var body: some View {
        FloatingChoiceMenu(selectedChoice: selectedChoice, accessibilityLabel: "Repost options", onSelect: onSelect)
    }
}

struct FavoriteChoiceMenu: View {
    let selectedChoice: FavoriteChoice?
    let onSelect: () -> Void

    var body: some View {
        FloatingChoiceMenu(selectedChoice: selectedChoice, accessibilityLabel: "Favorite options", onSelect: onSelect)
    }
}

private struct FloatingChoiceMenu<Choice: FloatingChoiceItem>: View {
    let selectedChoice: Choice?
    let accessibilityLabel: String
    let onSelect: () -> Void

    var body: some View {
        FloatingMenuSurface(width: FloatingMenuMetrics.choiceWidth, accessibilityLabel: accessibilityLabel) {
            ForEach(Array(Choice.allCases), id: \.self) { choice in
                FloatingMenuRow(
                    title: choice.title,
                    systemName: choice.systemName,
                    height: FloatingMenuMetrics.choiceRowHeight,
                    isSelected: selectedChoice == choice,
                    action: onSelect
                )
            }
        }
    }
}

private struct FloatingMenuSurface<Content: View>: View {
    let width: CGFloat
    let accessibilityLabel: String
    let content: Content

    init(width: CGFloat, accessibilityLabel: String, @ViewBuilder content: () -> Content) {
        self.width = width
        self.accessibilityLabel = accessibilityLabel
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, FloatingMenuMetrics.verticalPadding)
        .frame(width: width)
        .astrenzaGlass(tint: Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct FloatingMenuRow: View {
    let title: String
    let systemName: String
    let height: CGFloat
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(alignment: .center) {
                Capsule()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .astrenzaGlass(tint: Color.white.opacity(0.18), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 4)
                    }
                    .shadow(color: .white.opacity(0.14), radius: 10)
                    .opacity(isSelected ? 1 : 0)
            }
            .animation(.snappy(duration: 0.14), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct PostActionMenuDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.astrenzaSeparator)
            .padding(.vertical, 2)
            .padding(.leading, 44)
            .frame(height: FloatingMenuMetrics.dividerHeight)
    }
}
