import AstrenzaCore
import SwiftUI

struct ComposeDraft: Identifiable, Equatable {
    let id: String
    let text: String
    let contentWarning: String?
    let context: ComposeContext
    let tags: [[String]]
    let mediaCount: Int
    let mediaReferences: [NostrDraftMediaReference]

    init(
        id: String,
        text: String,
        contentWarning: String? = nil,
        context: ComposeContext = .post,
        tags: [[String]] = [],
        mediaCount: Int,
        mediaReferences: [NostrDraftMediaReference] = []
    ) {
        self.id = id
        self.text = text
        self.contentWarning = contentWarning
        self.context = context
        self.tags = tags
        self.mediaCount = mediaCount
        self.mediaReferences = mediaReferences
    }

    init(record: NostrDraftRecord) {
        self.init(
            id: record.draftID,
            text: record.text,
            contentWarning: record.contentWarning,
            context: ComposeContext(draftContext: record.context),
            tags: record.tags,
            mediaCount: record.media.count,
            mediaReferences: record.media
        )
    }
}

private extension ComposeContext {
    init(draftContext: NostrDraftContext) {
        switch draftContext {
        case .post:
            self = .post
        case .reply(let root, let parent, let recipientPubkeys):
            self = .reply(ComposeReplyContext(
                root: ComposeEventReference(draftReference: root),
                parent: ComposeEventReference(draftReference: parent),
                recipientPubkeys: recipientPubkeys
            ))
        case .quote(let target):
            self = .quote(ComposeQuoteContext(
                target: ComposeEventReference(draftReference: target)
            ))
        }
    }
}

private extension ComposeEventReference {
    init(draftReference: NostrDraftEventReference) {
        self.init(
            eventID: draftReference.eventID,
            relayHint: draftReference.relayHint,
            pubkey: draftReference.pubkey
        )
    }
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point14, style: .continuous)
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
            HStack(spacing: AstrenzaSpacing.point12) {
                Text(title)
                    .font(.astrenza(.point17, weight: .medium, design: .rounded))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.65))

                Spacer(minLength: 0)

                Image(systemName: systemName)
                    .font(.astrenza(.point20, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.65))
                    .frame(width: 28)
            }
            .padding(.horizontal, AstrenzaSpacing.point18)
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
                    .font(.astrenza(.point20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                HStack {
                    Button("Close", action: dismiss.callAsFunction)
                        .font(.astrenza(.point18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.astrenzaAccent)
                    Spacer()
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation(.snappy(duration: AstrenzaMotion.fast)) {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                        .font(.astrenza(.point18, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.astrenzaAccent)
                }
                .padding(.horizontal, AstrenzaSpacing.point20)
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
                                .font(.astrenza(.point17, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if draft.mediaCount > 0 {
                                Label("\(draft.mediaCount)", systemImage: "photo")
                                    .font(.astrenza(.point12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, AstrenzaSpacing.point18)
                        .frame(height: 58)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: AstrenzaRadius.point10, style: .continuous))
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
            .padding(.top, AstrenzaSpacing.point22)

            Spacer(minLength: 0)
        }
        .background(Color.astrenzaBackground)
    }
}
