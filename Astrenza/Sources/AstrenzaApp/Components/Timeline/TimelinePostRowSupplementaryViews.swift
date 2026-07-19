import SwiftUI

struct RelativeTimestampText: View {
    let createdAt: Int?

    var body: some View {
        if let createdAt {
            TimelineView(RelativeTimestampSchedule(createdAt: createdAt)) { context in
                Text(TimelineTimestampFormatter.relativeText(from: createdAt, now: context.date))
            }
        }
    }
}

struct RelativeTimestampSchedule: TimelineSchedule {
    let createdAt: Int

    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        AnySequence(
            sequence(
                first: startDate,
                next: { date in
                    TimelineTimestampFormatter.nextRelativeTextChangeDate(
                        from: createdAt,
                        after: date
                    )
                }
            )
        )
    }
}

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
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: AstrenzaRadius.point10, style: .continuous))
    }
}

private struct SensitiveTimelineOverlay: View {
    let contentWarning: TimelineContentWarning

    var body: some View {
        VStack(spacing: AstrenzaSpacing.point8) {
            HStack(spacing: AstrenzaSpacing.point6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.astrenza(.point13, weight: .black))
                Text("CONTENT WARNING")
                    .font(.astrenza(.point12, weight: .heavy, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, AstrenzaSpacing.point12)
            .frame(height: 30)
            .background(Color.secondary.opacity(0.92), in: Capsule())

            Text(contentWarning.displayReason)
                .font(.astrenza(.point12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("Tap to open detail")
                .font(.astrenza(.point11, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.astrenzaAccent)
        }
        .padding(.horizontal, AstrenzaSpacing.point22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.astrenzaBackground.opacity(0.18))
    }
}

struct RepostAttributionView: View {
    let attribution: TimelineRepostAttribution

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point6) {
            AvatarView(style: attribution.avatar, size: AstrenzaTimelineMetrics.contextAvatarSize)

            Text(attribution.author.primaryText)
                .font(.astrenza(.point12, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.astrenza(.point11, weight: .black))

            RelativeTimestampText(createdAt: attribution.createdAt)
                .font(.astrenza(.point11, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .foregroundStyle(Color.secondary)
        .padding(.leading, AstrenzaSpacing.point4)
        .padding(.trailing, AstrenzaSpacing.point9)
        .padding(.vertical, AstrenzaSpacing.point3)
        .background(Color.white.opacity(0.07), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimelineAuthorHeader: View {
    let author: TimelineAuthor
    let isLocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AstrenzaSpacing.point1) {
            HStack(spacing: AstrenzaSpacing.point5) {
                Text(author.primaryText)
                    .font(.system(size: AstrenzaTimelineMetrics.authorPrimaryFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.88)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.astrenza(.point10, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AstrenzaSpacing.point5) {
                Image(systemName: author.secondarySystemName)
                    .font(.astrenza(.point10, weight: .bold))
                    .foregroundStyle(secondaryIconStyle)
                    .frame(width: 12)

                Text(author.secondaryText)
                    .font(.system(size: AstrenzaTimelineMetrics.authorSecondaryFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondary)
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
    let onOpenRichURL: (URL) -> OpenURLAction.Result

    init(
        quotedPost: QuotedTimelinePost,
        onOpenRichURL: @escaping (URL) -> OpenURLAction.Result = { _ in .systemAction }
    ) {
        self.quotedPost = quotedPost
        self.onOpenRichURL = onOpenRichURL
    }

    var body: some View {
        HStack(alignment: .top, spacing: AstrenzaSpacing.point8) {
            AvatarView(style: quotedPost.avatar, size: AstrenzaTimelineMetrics.quotedAvatarSize)

            VStack(alignment: .leading, spacing: AstrenzaSpacing.point5) {
                HStack(alignment: .firstTextBaseline, spacing: AstrenzaSpacing.point6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(quotedPost.author.primaryText)
                            .font(.astrenza(.point12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(quotedPost.author.secondaryText)
                            .font(.astrenza(.point11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    RelativeTimestampText(createdAt: quotedPost.createdAt)
                        .font(.astrenza(.point11, weight: .bold, design: .rounded))
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
                    .environment(\.openURL, OpenURLAction(handler: onOpenRichURL))
                } else {
                    HStack(spacing: AstrenzaSpacing.point6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.astrenza(.point11, weight: .bold))
                        Text("Quoted note could not be loaded")
                            .font(.astrenza(.point12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.secondary)
                }
            }
        }
        .padding(.horizontal, AstrenzaSpacing.point10)
        .padding(.vertical, AstrenzaSpacing.point8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.astrenzaAttachmentBackground, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}
