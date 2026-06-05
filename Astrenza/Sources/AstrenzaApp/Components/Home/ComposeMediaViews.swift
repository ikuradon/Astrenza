import SwiftUI
import UIKit

struct ComposeSelectedMedia: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    var altText: String?

    static func == (lhs: ComposeSelectedMedia, rhs: ComposeSelectedMedia) -> Bool {
        lhs.id == rhs.id
    }
}

struct ComposeSelectedMediaStrip: View {
    let items: [ComposeSelectedMedia]
    let onMenu: (ComposeSelectedMedia) -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onMenu(item)
                        } label: {
                            ComposeSelectedMediaThumbnail(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Selected media")
                        .accessibilityIdentifier(index == 0 ? "compose.media.thumbnail" : "compose.media.thumbnail.\(index)")
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, items.count > 1 ? 28 : 0)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

            if items.count > 1 {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .black))
                    Text("\(items.count)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Color.black.opacity(0.58), in: Capsule())
                .padding(.trailing, 4)
                .padding(.bottom, 8)
                .accessibilityLabel("\(items.count) selected media")
                .accessibilityIdentifier("compose.media.count")
            }
        }
        .frame(height: 104)
    }
}

struct ComposeSelectedMediaThumbnail: View {
    let item: ComposeSelectedMedia

    var body: some View {
        Image(uiImage: item.image)
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if item.altText != nil {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .padding(5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ComposeMediaActionMenu: View {
    let onPreview: () -> Void
    let onAddDescription: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            mediaMenuButton("Preview", systemName: "eye", action: onPreview)
            Divider().overlay(Color.white.opacity(0.12))
            mediaMenuButton("Add Description", systemName: "pencil", action: onAddDescription)
            Divider().overlay(Color.black.opacity(0.16))
                .frame(height: 10)
                .background(Color.black.opacity(0.16))
            mediaMenuButton("Remove", systemName: "minus.circle", tint: .red, action: onRemove)
        }
        .frame(width: 268)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
        .accessibilityLabel("Media actions")
    }

    private func mediaMenuButton(
        _ title: String,
        systemName: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("compose.media.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}
