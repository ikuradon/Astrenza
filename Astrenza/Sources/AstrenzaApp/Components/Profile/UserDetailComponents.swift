import SwiftUI

struct ProfileBannerView: View {
    let style: ProfileBannerStyle

    var body: some View {
        ZStack {
            LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: style.symbolName)
                .font(.system(size: 118, weight: .black))
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
    let onOpenMedia: (TimelineMedia) -> Void
    @ViewBuilder let overlay: () -> Overlay

    init(
        profile: UserProfile,
        size: CGFloat,
        label: String,
        onOpenMedia: @escaping (TimelineMedia) -> Void,
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
            onOpenMedia(profile.avatarMedia)
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
        onOpenMedia: @escaping (TimelineMedia) -> Void
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
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
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
        HStack(spacing: 15) {
            Image(systemName: systemName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34)

            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .contentShape(Rectangle())
    }
}

struct UserFeaturedHashtagRow: View {
    let hashtag: UserFeaturedHashtag

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hashtag.tag)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(hashtag.lastUsed)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(hashtag.count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .contentShape(Rectangle())
    }
}
