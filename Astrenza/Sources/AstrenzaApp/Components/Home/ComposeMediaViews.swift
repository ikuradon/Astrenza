import SwiftUI
import UIKit

struct ComposeSelectedMedia: Identifiable, Equatable {
    let id: UUID
    let image: UIImage
    let localURL: URL?
    let mimeType: String
    var altText: String?

    init(
        id: UUID = UUID(),
        image: UIImage,
        localURL: URL? = nil,
        mimeType: String = "image/jpeg",
        altText: String?
    ) {
        self.id = id
        self.image = image
        self.localURL = localURL
        self.mimeType = mimeType
        self.altText = altText
    }

    var uploadRequest: ComposeMediaUploadRequest? {
        guard let localURL else { return nil }
        let pixelSize = image.pixelSize
        return ComposeMediaUploadRequest(
            id: id,
            localURL: localURL,
            mimeType: mimeType,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            altText: altText
        )
    }

    static func == (lhs: ComposeSelectedMedia, rhs: ComposeSelectedMedia) -> Bool {
        lhs.id == rhs.id
    }
}

private extension UIImage {
    var pixelSize: CGSize {
        if let cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

struct ComposeSelectedMediaStrip: View {
    let items: [ComposeSelectedMedia]
    let onMenu: (ComposeSelectedMedia) -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AstrenzaSpacing.point10) {
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
                .padding(.vertical, AstrenzaSpacing.point2)
                .padding(.trailing, items.count > 1 ? AstrenzaSpacing.point28 : 0)
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
                HStack(spacing: AstrenzaSpacing.point3) {
                    Image(systemName: "chevron.right")
                        .font(.astrenza(.point10, weight: .black))
                    Text("\(items.count)")
                        .font(.astrenza(.point11, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AstrenzaSpacing.point8)
                .frame(height: 24)
                .background(Color.black.opacity(0.58), in: Capsule())
                .padding(.trailing, AstrenzaSpacing.point4)
                .padding(.bottom, AstrenzaSpacing.point8)
                .accessibilityLabel("\(items.count) selected media")
                .accessibilityIdentifier("compose.media.count")
            }
        }
        .frame(height: 104)
    }
}

struct ComposeMediaPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let media: ComposeSelectedMedia

    var body: some View {
        NavigationStack {
            Image(uiImage: media.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.astrenzaBackground)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: dismiss.callAsFunction)
                    }
                }
        }
    }
}

struct ComposeMediaAltTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var altText: String
    let onSave: (String) -> Void

    init(media: ComposeSelectedMedia, onSave: @escaping (String) -> Void) {
        image = media.image
        _altText = State(initialValue: media.altText ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AstrenzaSpacing.point16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(
                        cornerRadius: AstrenzaRadius.point10,
                        style: .continuous
                    ))

                TextField("Describe this image", text: $altText, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)

                Spacer(minLength: 0)
            }
            .padding(AstrenzaSpacing.point18)
            .background(Color.astrenzaBackground)
            .navigationTitle("Image Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(altText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}


struct ComposeSelectedMediaThumbnail: View {
    let item: ComposeSelectedMedia

    var body: some View {
        Image(uiImage: item.image)
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if item.altText != nil {
                    Image(systemName: "text.bubble")
                        .font(.astrenza(.point12, weight: .black))
                        .foregroundStyle(.white)
                        .padding(AstrenzaSpacing.point6)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .padding(AstrenzaSpacing.point5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous))
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point14, style: .continuous)
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
            HStack(spacing: AstrenzaSpacing.point12) {
                Text(title)
                    .font(.astrenza(.point17, weight: .medium, design: .rounded))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Image(systemName: systemName)
                    .font(.astrenza(.point20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
            }
            .padding(.horizontal, AstrenzaSpacing.point18)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("compose.media.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}
