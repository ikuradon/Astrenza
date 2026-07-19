import SwiftUI

struct ProfileBannerView: View {
    let style: ProfileBannerStyle

    var body: some View {
        ZStack {
            LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: style.symbolName)
                .font(.astrenza(.point118, weight: .black))
                .foregroundStyle(.white.opacity(0.18))
                .offset(x: 96, y: 34)

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.18)

            LinearGradient(
                colors: [.clear, Color.astrenzaBackground.opacity(0.92)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .clipped()
    }
}

struct ProfileAvatarMediaButton<Overlay: View>: View {
    let profile: UserProfile
    let size: CGFloat
    let label: String
    let onOpenMedia: (TimelineMedia, Int) -> Void
    @ViewBuilder let overlay: () -> Overlay

    init(
        profile: UserProfile,
        size: CGFloat,
        label: String,
        onOpenMedia: @escaping (TimelineMedia, Int) -> Void,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.profile = profile
        self.size = size
        self.label = label
        self.onOpenMedia = onOpenMedia
        self.overlay = overlay
    }

    var body: some View {
        Button {
            onOpenMedia(profile.avatarMedia, 0)
        } label: {
            AvatarView(style: profile.avatar, size: size)
                .overlay {
                    overlay()
                }
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .accessibilityLabel(label)
    }
}

extension ProfileAvatarMediaButton where Overlay == EmptyView {
    init(
        profile: UserProfile,
        size: CGFloat,
        label: String,
        onOpenMedia: @escaping (TimelineMedia, Int) -> Void
    ) {
        self.init(
            profile: profile,
            size: size,
            label: label,
            onOpenMedia: onOpenMedia
        ) {
            EmptyView()
        }
    }
}

extension UserProfile {
    var avatarMedia: TimelineMedia {
        .gallery([
            MediaTile(
                title: "\(author.primaryText) Avatar",
                colors: [avatar.primary, avatar.secondary],
                symbolName: avatar.symbolName
            )
        ])
    }

    var bannerMedia: TimelineMedia {
        .gallery([
            MediaTile(
                title: "\(author.primaryText) Hero",
                colors: banner.colors,
                symbolName: banner.symbolName
            )
        ])
    }
}

struct UserProfileMetricCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: AstrenzaSpacing.point8) {
            Text(title)
                .font(.astrenza(.point15, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.astrenza(.point32, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}

struct UserProfileLinkRow: View {
    let systemName: String
    let title: String
    let value: String?

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point15) {
            Image(systemName: systemName)
                .font(.astrenza(.point25, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34)

            Text(title)
                .font(.astrenza(.point19, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: AstrenzaSpacing.point8)

            if let value {
                Text(value)
                    .font(.astrenza(.point18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.astrenza(.point18, weight: .heavy))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AstrenzaSpacing.point16)
        .frame(height: 66)
        .contentShape(Rectangle())
    }
}

struct UserFeaturedHashtagRow: View {
    let hashtag: UserFeaturedHashtag

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point10) {
            VStack(alignment: .leading, spacing: AstrenzaSpacing.point2) {
                Text(hashtag.tag)
                    .font(.astrenza(.point20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(hashtag.lastUsed)
                    .font(.astrenza(.point14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AstrenzaSpacing.point8)

            Text("\(hashtag.count)")
                .font(.astrenza(.point18, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.astrenza(.point18, weight: .heavy))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AstrenzaSpacing.point18)
        .frame(height: 66)
        .contentShape(Rectangle())
    }
}
