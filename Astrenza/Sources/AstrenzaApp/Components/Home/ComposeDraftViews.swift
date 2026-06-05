import SwiftUI

struct ComposeDraft: Identifiable, Equatable {
    let id: String
    let text: String
    let mediaCount: Int
}

struct ComposeSettingsMenu: View {
    let draftCount: Int
    let onBrowseFiles: () -> Void
    let onCamera: () -> Void
    let onDrafts: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            settingsButton("Browse Files...", systemName: "doc", action: onBrowseFiles)
            Divider().overlay(Color.white.opacity(0.12))
            settingsButton("Camera", systemName: "camera", action: onCamera)
            Divider().overlay(Color.white.opacity(0.12))
            settingsButton(
                draftCount > 0 ? "Drafts (\(draftCount))" : "Drafts",
                systemName: "list.bullet.rectangle",
                isEnabled: onDrafts != nil,
                action: onDrafts ?? {}
            )
        }
        .frame(width: 278)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 22, y: 12)
        .accessibilityLabel("Composer settings menu")
    }

    private func settingsButton(
        _ title: String,
        systemName: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.65))

                Spacer(minLength: 0)

                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.65))
                    .frame(width: 28)
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier("compose.settings.\(title.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: ""))")
    }
}

struct ComposeDraftsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .inactive
    let drafts: [ComposeDraft]
    let onDelete: (IndexSet) -> Void
    let onSelect: (ComposeDraft) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Drafts")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                HStack {
                    Button("Close", action: dismiss.callAsFunction)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.astrenzaAccent)
                    Spacer()
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation(.snappy(duration: 0.18)) {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.astrenzaAccent)
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 72)

            Divider().overlay(Color.astrenzaSeparator)

            List {
                ForEach(drafts) { draft in
                    Button {
                        onSelect(draft)
                    } label: {
                        HStack {
                            Text(draft.text.isEmpty ? "Media draft" : draft.text)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if draft.mediaCount > 0 {
                                Label("\(draft.mediaCount)", systemImage: "photo")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onDelete(perform: onDelete)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
        .background(Color.astrenzaBackground)
        .preferredColorScheme(.dark)
    }
}
