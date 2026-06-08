import SwiftUI

struct SensitiveTimelineContent<Content: View>: View {
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
        .frame(height: 98)
        .clipped()
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SensitiveTimelineOverlay: View {
    let contentWarning: TimelineContentWarning

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .black))
                Text("CONTENT WARNING")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.secondary.opacity(0.92), in: Capsule())

            Text(contentWarning.displayReason)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("Tap to open detail")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.astrenzaAccent)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.astrenzaBackground.opacity(0.18))
    }
}

struct RepostAttributionView: View {
    let attribution: TimelineRepostAttribution

    var body: some View {
        HStack(spacing: 6) {
            AvatarView(style: attribution.avatar, size: AstrenzaTimelineMetrics.contextAvatarSize)

            Text(attribution.author.primaryText)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .black))

            Text(attribution.timestamp)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.07), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimelineAuthorHeader: View {
    let author: TimelineAuthor
    let isLocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(author.primaryText)
                    .font(.system(size: AstrenzaTimelineMetrics.authorPrimaryFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.88)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                Image(systemName: author.secondarySystemName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(secondaryIconStyle)
                    .frame(width: 12)

                Text(author.secondaryText)
                    .font(.system(size: AstrenzaTimelineMetrics.authorSecondaryFontSize, weight: .semibold, design: .rounded))
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

struct QuotedPostCard: View {
    let quotedPost: QuotedTimelinePost

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(style: quotedPost.avatar, size: AstrenzaTimelineMetrics.quotedAvatarSize)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(quotedPost.author.primaryText)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(quotedPost.author.secondaryText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    Text(quotedPost.timestamp)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }

                if quotedPost.isAvailable {
                    TimelinePostBodyText(
                        text: quotedPost.body,
                        richContent: quotedPost.richBody,
                        mention: nil,
                        lineLimit: 3
                    )
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .bold))
                        Text("Quoted note could not be loaded")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.astrenzaAttachmentBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}
