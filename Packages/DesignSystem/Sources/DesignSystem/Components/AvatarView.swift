import SwiftUI

public struct AvatarView: View {
    @Environment(\.appTheme) private var theme

    private let imageURL: URL?
    private let initials: String
    private let size: Double

    public init(imageURL: URL? = nil, initials: String = "", size: Double = TimelineRowMetrics().avatarSize) {
        self.imageURL = imageURL
        self.initials = initials
        self.size = size
    }

    public var body: some View {
        ZStack {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: CGFloat(size), height: CGFloat(size))
        .clipShape(Circle())
        .overlay {
            Circle().stroke(theme.color(.separator), lineWidth: DSSpacing.hairline.cgFloat)
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(theme.color(.placeholder))
            if initials.isEmpty {
                Image(systemName: DSIcon.avatarPlaceholder.systemName)
                    .font(DSIcon.avatarPlaceholder.font(for: .tab, weight: .medium))
                    .foregroundStyle(theme.color(.textSecondary))
            } else {
                Text(String(initials.prefix(2)).uppercased())
                    .font(DSTypography.badge.font)
                    .foregroundStyle(theme.color(.textPrimary))
            }
        }
    }
}
