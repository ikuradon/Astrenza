import SwiftUI

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
    let onActionEvent: (TimelinePostActionEvent) -> Void
    let onDismissActionMenu: () -> Void
    @State private var didHandleActionGesture = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let repostedBy = post.repostedBy {
                RepostAttributionView(attribution: repostedBy)
                    .padding(.leading, 82)
                    .padding(.trailing, 16)
            }

            HStack(alignment: .top, spacing: 12) {
                AvatarView(style: post.avatar, size: 54)

                VStack(alignment: .leading, spacing: 8) {
                    header

                    if let context = post.context {
                        ContextPill(text: context)
                    }

                    Text(post.body)
                        .font(.system(size: 18, weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(Color.astrenzaText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let quotedPost = post.quotedPost {
                        QuotedPostCard(quotedPost: quotedPost)
                    }

                    if let media = post.media {
                        TimelineMediaView(media: media)
                            .padding(.top, 2)
                    }

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
        .onTapGesture {
            if didHandleActionGesture {
                didHandleActionGesture = false
                return
            }

            onDismissActionMenu()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TimelineAuthorHeader(author: post.author, isLocked: post.isLocked)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(post.timestamp)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
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
                    sendActionEvent(.repost, phase: .longPressBegan)
                },
                onLongPressDragChanged: { location in
                    sendActionEvent(.repost, phase: .dragChanged(location))
                },
                onLongPressDragEnded: { location in
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
                    sendActionEvent(.favorite, phase: .longPressBegan)
                },
                onLongPressDragChanged: { location in
                    sendActionEvent(.favorite, phase: .dragChanged(location))
                },
                onLongPressDragEnded: { location in
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
                    sendActionEvent(.more, phase: .longPressBegan)
                },
                onLongPressDragChanged: { location in
                    sendActionEvent(.more, phase: .dragChanged(location))
                },
                onLongPressDragEnded: { location in
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
    let onSelect: () -> Void

    var body: some View {
        FloatingMenuSurface(width: FloatingMenuMetrics.actionWidth, accessibilityLabel: "Post actions") {
            ForEach(Array(PostActionChoice.allCases), id: \.self) { choice in
                FloatingMenuRow(
                    title: choice.title,
                    systemName: choice.systemName,
                    height: FloatingMenuMetrics.actionRowHeight,
                    isSelected: selectedChoice == choice,
                    action: onSelect
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

private struct ContextPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}
