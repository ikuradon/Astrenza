import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ComposeSheetMode {
    case post
    case reply

    var title: String {
        switch self {
        case .post: "Compose"
        case .reply: "Reply"
        }
    }

    var placeholder: String {
        switch self {
        case .post: "Say something..."
        case .reply: "Write a reply..."
        }
    }

    var actionTitle: String {
        switch self {
        case .post: "Post"
        case .reply: "Reply"
        }
    }
}

struct ComposeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool
    let mode: ComposeSheetMode
    @State private var text = ""
    @State private var sensitiveReason = ""
    @State private var isSensitiveReasonVisible = false
    @State private var isUserSwitcherPresented = false
    @State private var isCameraPresented = false
    @State private var isFileImporterPresented = false
    @State private var isCustomEmojiPickerPresented = false
    @State private var isContinuousCustomEmojiInput = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedMediaItems: [ComposeSelectedMedia] = []
    @State private var activeMediaMenuItem: ComposeSelectedMedia?
    @State private var isComposerSettingsPresented = false
    @State private var isDraftCloseDialogPresented = false
    @State private var isDraftsViewPresented = false
    @AppStorage("astrenza.mockComposeDraftText") private var savedDraftText = ""
    @AppStorage("astrenza.mockComposeDraftMediaCount") private var savedDraftMediaCount = 0
    private let characterLimit = 500
    private let accent = Color.astrenzaAccent

    init(mode: ComposeSheetMode = .post) {
        self.mode = mode
    }

    private var remainingCharacters: Int {
        characterLimit - text.count
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && remainingCharacters >= 0
    }

    private var hasDraftContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedMediaItems.isEmpty
    }

    private var savedDrafts: [ComposeDraft] {
        guard !savedDraftText.isEmpty || savedDraftMediaCount > 0 else { return [] }
        return [
            ComposeDraft(
                id: "mock-draft-1",
                text: savedDraftText,
                mediaCount: savedDraftMediaCount
            )
        ]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                navigationBar

                Divider().overlay(Color.astrenzaSeparator)

                editorArea

                Spacer(minLength: 0)
            }

            if isUserSwitcherPresented {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.24, bounce: 0.14)) {
                            isUserSwitcherPresented = false
                        }
                    }

                UserSwitcherMenu {
                    withAnimation(.spring(duration: 0.24, bounce: 0.14)) {
                        isUserSwitcherPresented = false
                    }
                }
                .padding(.leading, 18)
                .padding(.top, 154)
                .transition(.scale(scale: 0.72, anchor: .topLeading).combined(with: .opacity))
                .zIndex(20)
            }

            if let media = activeMediaMenuItem {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.22, bounce: 0.12)) {
                            activeMediaMenuItem = nil
                        }
                    }

                ComposeMediaActionMenu(
                    onPreview: {
                        activeMediaMenuItem = nil
                    },
                    onAddDescription: {
                        markMediaDescriptionRequested(media)
                        activeMediaMenuItem = nil
                    },
                    onRemove: {
                        removeMedia(media)
                        activeMediaMenuItem = nil
                    }
                )
                .padding(.leading, 118)
                .padding(.top, 356)
                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                .zIndex(30)
            }

            if isComposerSettingsPresented {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.22, bounce: 0.12)) {
                            isComposerSettingsPresented = false
                        }
                    }

                ComposeSettingsMenu(
                    draftCount: savedDrafts.count,
                    onBrowseFiles: {
                        isComposerSettingsPresented = false
                        isFileImporterPresented = true
                    },
                    onCamera: {
                        isComposerSettingsPresented = false
                        isCameraPresented = true
                    },
                    onDrafts: savedDrafts.isEmpty ? nil : {
                        isComposerSettingsPresented = false
                        isEditorFocused = false
                        isDraftsViewPresented = true
                    }
                )
                .padding(.leading, 162)
                .padding(.top, 360)
                .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
                .zIndex(25)
            }
        }
        .background(Color.astrenzaBackground)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomComposerControls
        }
        .confirmationDialog("Camera", isPresented: $isCameraPresented, titleVisibility: .visible) {
            Button("Open Camera") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Camera capture is mocked in this compose prototype.")
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { _ in }
        .confirmationDialog("", isPresented: $isDraftCloseDialogPresented, titleVisibility: .hidden) {
            Button("Ignore Draft", role: .destructive) {
                dismiss()
            }
            Button("Save Draft") {
                saveCurrentDraft()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isDraftsViewPresented) {
            ComposeDraftsView(
                drafts: savedDrafts,
                onDelete: { _ in
                    deleteSavedDraft()
                }
            ) { draft in
                text = draft.text
                isDraftsViewPresented = false
                isEditorFocused = true
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                isEditorFocused = true
            }
        }
        .onChange(of: text) { _, newValue in
            if newValue.count > characterLimit {
                text = String(newValue.prefix(characterLimit))
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            loadSelectedPhotos(newItems)
        }
    }

    private var navigationBar: some View {
        ZStack {
            Text(mode.title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            HStack {
                Button("Close", action: closeComposer)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)

                Spacer()

                Button(mode.actionTitle) {
                    dismiss()
                }
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(canSubmit ? accent : Color.secondary.opacity(0.55))
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
    }

    private var editorArea: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
                    isUserSwitcherPresented.toggle()
                }
            } label: {
                UserSwitchButton(isExpanded: isUserSwitcherPresented)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .accessibilityLabel("Switch user")

            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(mode.placeholder)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary.opacity(0.78))
                            .padding(.top, 26)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .focused($isEditorFocused)
                        .padding(.top, 16)
                        .padding(.leading, -4)
                        .frame(minHeight: selectedMediaItems.isEmpty ? 320 : 64)
                        .accessibilityLabel(mode.placeholder)
                }

                if !selectedMediaItems.isEmpty {
                    ComposeSelectedMediaStrip(items: selectedMediaItems) { media in
                        withAnimation(.spring(duration: 0.22, bounce: 0.12)) {
                            activeMediaMenuItem = media
                        }
                    }
                    .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
                    .padding(.leading, 2)
                }
            }

            Text("\(remainingCharacters)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(remainingCharacters < 0 ? .red : Color.secondary.opacity(0.78))
                .padding(.top, 26)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private var bottomComposerControls: some View {
        VStack(spacing: 0) {
            if isSensitiveReasonVisible {
                sensitiveReasonField
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isCustomEmojiPickerPresented {
                ComposeCustomEmojiPicker(isContinuousInput: isContinuousCustomEmojiInput) { candidate in
                    if isContinuousCustomEmojiInput {
                        insertContinuousCustomEmoji(candidate.shortcode)
                    } else {
                        insertStandaloneToken(candidate.shortcode)
                        withAnimation(.spring(duration: 0.24, bounce: 0.12)) {
                            isCustomEmojiPickerPresented = false
                        }
                    }
                } onReturn: {
                    finishContinuousCustomEmojiInput()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let completion = activeCompletion {
                ComposeCompletionBar(completion: completion) { value in
                    insertCompletion(value)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                composeToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.22, bounce: 0.1), value: activeCompletion?.trigger)
        .animation(.spring(duration: 0.22, bounce: 0.1), value: isSensitiveReasonVisible)
        .animation(.spring(duration: 0.24, bounce: 0.12), value: isCustomEmojiPickerPresented)
    }

    private var sensitiveReasonField: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(accent)

            TextField("Sensitive reason", text: $sensitiveReason)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)
                .submitLabel(.done)
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.26), lineWidth: 1)
        }
    }

    private var composeToolbar: some View {
        HStack(spacing: 0) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 8, matching: .images) {
                ComposeToolIcon(systemName: "photo.on.rectangle.angled")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        isCameraPresented = true
                    }
            )
            .accessibilityLabel("Add media")

            ComposeEmojiToolButton(
                onTap: { presentCustomEmojiPicker(isContinuous: false) },
                onLongPress: { presentCustomEmojiPicker(isContinuous: true) }
            )

            ComposeToolButton(systemName: "exclamationmark.triangle", label: "Content warning") {
                isCustomEmojiPickerPresented = false
                isContinuousCustomEmojiInput = false
                isSensitiveReasonVisible.toggle()
            }

            ComposeToolButton(systemName: "at", label: "Mention") {
                isCustomEmojiPickerPresented = false
                isContinuousCustomEmojiInput = false
                insertTrigger("@")
            }

            ComposeToolButton(systemName: "number", label: "Hashtag") {
                isCustomEmojiPickerPresented = false
                isContinuousCustomEmojiInput = false
                insertTrigger("#")
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(duration: 0.22, bounce: 0.12)) {
                    isComposerSettingsPresented.toggle()
                }
            } label: {
                ComposeToolIcon(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Composer settings")
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(Color.black.opacity(0.28))
    }

    private var activeCompletion: ComposeCompletion? {
        guard text.last?.isWhitespace != true else { return nil }
        guard let token = text.split(whereSeparator: \.isWhitespace).last else { return nil }
        guard let trigger = token.first, ["@", "#", ":"].contains(trigger) else { return nil }
        let query = String(token.dropFirst()).lowercased()

        switch trigger {
        case "@":
            return ComposeCompletion(
                trigger: "@",
                values: ComposeMentionCandidate.mockValues
                    .filter { !query.isEmpty && $0.searchText.contains(query) }
                    .map(\.insertionText)
            )
        case "#":
            return ComposeCompletion(
                trigger: "#",
                values: ComposeHashtagCandidate.recentValues
                    .filter { query.isEmpty || $0.tag.lowercased().contains(query) }
                    .map(\.tag)
            )
        case ":":
            return ComposeCompletion(
                trigger: ":",
                values: ComposeCustomEmojiCandidate.mockValues
                    .filter { !query.isEmpty && $0.shortcode.lowercased().contains(query) }
                    .map(\.shortcode)
            )
        default:
            return nil
        }
    }

    private func insertTrigger(_ trigger: String) {
        if !text.isEmpty && !text.last!.isWhitespace {
            text += " "
        }
        text += trigger
        isEditorFocused = true
    }

    private func insertCompletion(_ value: String) {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let last = parts.last, ["@", "#", ":"].contains(last.first ?? " ") else {
            insertTrigger(value)
            return
        }

        text.removeLast(last.count)
        text += "\(value) "
        isEditorFocused = true
    }

    private func insertStandaloneToken(_ value: String) {
        if !text.isEmpty && !text.last!.isWhitespace {
            text += " "
        }
        text += "\(value) "
        isEditorFocused = true
    }

    private func insertContinuousCustomEmoji(_ value: String) {
        if !text.isEmpty && !text.last!.isWhitespace {
            text += "\u{200B}"
        }
        text += value
    }

    private func presentCustomEmojiPicker(isContinuous: Bool) {
        isEditorFocused = false
        isContinuousCustomEmojiInput = isContinuous
        withAnimation(.spring(duration: 0.24, bounce: 0.12)) {
            isCustomEmojiPickerPresented = true
        }
    }

    private func finishContinuousCustomEmojiInput() {
        if !text.isEmpty && !text.last!.isWhitespace {
            text += " "
        }
        isContinuousCustomEmojiInput = false
        withAnimation(.spring(duration: 0.24, bounce: 0.12)) {
            isCustomEmojiPickerPresented = false
        }
        isEditorFocused = true
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var loadedItems: [ComposeSelectedMedia] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                loadedItems.append(
                    ComposeSelectedMedia(
                        image: image,
                        altText: nil
                    )
                )
            }
            await MainActor.run {
                selectedMediaItems.append(contentsOf: loadedItems)
                selectedPhotoItems = []
            }
        }
    }

    private func markMediaDescriptionRequested(_ media: ComposeSelectedMedia) {
        guard let index = selectedMediaItems.firstIndex(where: { $0.id == media.id }) else { return }
        selectedMediaItems[index].altText = "Description pending..."
    }

    private func removeMedia(_ media: ComposeSelectedMedia) {
        selectedMediaItems.removeAll { $0.id == media.id }
    }

    private func closeComposer() {
        if hasDraftContent {
            isDraftCloseDialogPresented = true
        } else {
            dismiss()
        }
    }

    private func saveCurrentDraft() {
        savedDraftText = text
        savedDraftMediaCount = selectedMediaItems.count
        isDraftCloseDialogPresented = false
        dismiss()
    }

    private func deleteSavedDraft() {
        savedDraftText = ""
        savedDraftMediaCount = 0
    }

}

private struct ComposeToolButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    init(systemName: String, label: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ComposeToolIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ComposeDraft: Identifiable, Equatable {
    let id: String
    let text: String
    let mediaCount: Int
}

private struct ComposeSettingsMenu: View {
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

private struct ComposeDraftsView: View {
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

private struct ComposeSelectedMedia: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    var altText: String?

    static func == (lhs: ComposeSelectedMedia, rhs: ComposeSelectedMedia) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ComposeSelectedMediaStrip: View {
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

private struct ComposeSelectedMediaThumbnail: View {
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

private struct ComposeMediaActionMenu: View {
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

private struct ComposeEmojiToolButton: View {
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        ComposeToolIcon(systemName: "face.smiling")
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.45, perform: onLongPress)
            .accessibilityLabel("Emoji")
            .accessibilityAddTraits(.isButton)
    }
}

private struct ComposeToolIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Color.astrenzaAccent)
            .frame(width: 43, height: 44)
            .contentShape(Rectangle())
    }
}

private struct ComposeCompletion: Equatable {
    let trigger: Character
    let values: [String]

    var mentionCandidates: [ComposeMentionCandidate] {
        guard trigger == "@" else { return [] }
        return ComposeMentionCandidate.mockValues.filter { values.contains($0.insertionText) }
    }

    var hashtagCandidates: [ComposeHashtagCandidate] {
        guard trigger == "#" else { return [] }
        return ComposeHashtagCandidate.recentValues.filter { values.contains($0.tag) }
    }

    var customEmojiCandidates: [ComposeCustomEmojiCandidate] {
        guard trigger == ":" else { return [] }
        return ComposeCustomEmojiCandidate.mockValues.filter { values.contains($0.shortcode) }
    }
}

private struct ComposeCompletionBar: View {
    let completion: ComposeCompletion
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if completion.trigger == "@" {
                    if completion.mentionCandidates.isEmpty {
                        Text("Start Typing a User...")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(completion.mentionCandidates.prefix(6)) { candidate in
                            Button {
                                onSelect(candidate.insertionText)
                            } label: {
                                ComposeMentionCandidateCell(candidate: candidate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if completion.trigger == "#" {
                    ForEach(completion.hashtagCandidates.prefix(6)) { candidate in
                        Button {
                            onSelect(candidate.tag)
                        } label: {
                            ComposeHashtagCandidateCell(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                    }
                } else if completion.trigger == ":" {
                    if completion.customEmojiCandidates.isEmpty {
                        Text("Start Typing a Shortcode...")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(completion.customEmojiCandidates.prefix(8)) { candidate in
                            Button {
                                onSelect(candidate.shortcode)
                            } label: {
                                ComposeCustomEmojiCandidateCell(candidate: candidate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    ForEach(completion.values.prefix(6), id: \.self) { value in
                        Button {
                            onSelect(value)
                        } label: {
                            Text(value)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(Color.black.opacity(0.28))
        .accessibilityLabel("Input suggestions")
    }
}

private struct ComposeMentionCandidate: Identifiable, Equatable {
    let id: String
    let displayName: String
    let handle: String
    let avatar: AvatarStyle

    var insertionText: String {
        "@\(id)"
    }

    var searchText: String {
        "\(displayName) \(handle) \(insertionText)".lowercased()
    }

    static func == (lhs: ComposeMentionCandidate, rhs: ComposeMentionCandidate) -> Bool {
        lhs.id == rhs.id
    }

    static let mockValues: [ComposeMentionCandidate] = [
        ComposeMentionCandidate(
            id: "ivory",
            displayName: "Ivory by Tapbots",
            handle: "@ivory@tapbots.social",
            avatar: AvatarStyle(primary: .indigo, secondary: .purple, symbolName: "quote.bubble.fill")
        ),
        ComposeMentionCandidate(
            id: "aureoleark",
            displayName: "User Beta",
            handle: "@aureoleark@mock.example",
            avatar: AvatarStyle(primary: .cyan, secondary: .blue, symbolName: "person.crop.circle.fill")
        ),
        ComposeMentionCandidate(
            id: "thunder",
            displayName: "User Gamma",
            handle: "@thunder@mock.example",
            avatar: AvatarStyle(primary: .blue, secondary: .indigo, symbolName: "cloud.bolt.fill")
        )
    ]
}

private struct ComposeMentionCandidateCell: View {
    let candidate: ComposeMentionCandidate

    var body: some View {
        HStack(spacing: 9) {
            AvatarView(style: candidate.avatar, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(candidate.handle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 138, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct ComposeHashtagCandidate: Identifiable, Equatable {
    let tag: String
    let recency: String
    let isPinned: Bool

    var id: String { tag }

    static let recentValues: [ComposeHashtagCandidate] = [
        ComposeHashtagCandidate(tag: "#fedeloper", recency: "Used 6 years ago", isPinned: true),
        ComposeHashtagCandidate(tag: "#EJUG", recency: "Used recently", isPinned: false),
        ComposeHashtagCandidate(tag: "#degoogle", recency: "Used once in 7 days", isPinned: false),
        ComposeHashtagCandidate(tag: "#nostr", recency: "Used recently", isPinned: false),
        ComposeHashtagCandidate(tag: "#timeline", recency: "Used last week", isPinned: false),
        ComposeHashtagCandidate(tag: "#relay", recency: "Used last week", isPinned: false)
    ]
}

private struct ComposeHashtagCandidateCell: View {
    let candidate: ComposeHashtagCandidate

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: candidate.isPinned ? "tag.fill" : "clock.arrow.circlepath")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.tag)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(candidate.recency)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 128, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct ComposeCustomEmojiCandidate: Identifiable, Equatable {
    let shortcode: String
    let glyph: String
    let tint: Color

    var id: String { shortcode }

    static let mockValues: [ComposeCustomEmojiCandidate] = [
        ComposeCustomEmojiCandidate(shortcode: ":60fpsparrot:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":aicp:", glyph: "🤖", tint: .yellow),
        ComposeCustomEmojiCandidate(shortcode: ":android:", glyph: "🤖", tint: .green),
        ComposeCustomEmojiCandidate(shortcode: ":angelparrot:", glyph: "🪽", tint: .mint),
        ComposeCustomEmojiCandidate(shortcode: ":astrenza:", glyph: "✦", tint: .purple),
        ComposeCustomEmojiCandidate(shortcode: ":apple:", glyph: "🍎", tint: .red)
    ]

    static let customPickerValues: [ComposeCustomEmojiCandidate] = [
        ComposeCustomEmojiCandidate(shortcode: ":aicp:", glyph: "🤖", tint: .yellow),
        ComposeCustomEmojiCandidate(shortcode: ":android:", glyph: "🤖", tint: .green),
        ComposeCustomEmojiCandidate(shortcode: ":dejavu:", glyph: "♨︎", tint: .orange),
        ComposeCustomEmojiCandidate(shortcode: ":sleepycat:", glyph: "🐱", tint: .brown),
        ComposeCustomEmojiCandidate(shortcode: ":git:", glyph: "◆", tint: .red),
        ComposeCustomEmojiCandidate(shortcode: ":github:", glyph: "◕", tint: .gray),
        ComposeCustomEmojiCandidate(shortcode: ":gitlab:", glyph: "🦊", tint: .orange),
        ComposeCustomEmojiCandidate(shortcode: ":intel:", glyph: "intel", tint: .blue),
        ComposeCustomEmojiCandidate(shortcode: ":spinner:", glyph: "◌", tint: .gray),
        ComposeCustomEmojiCandidate(shortcode: ":mastodon:", glyph: "m", tint: .blue),
        ComposeCustomEmojiCandidate(shortcode: ":rustacean:", glyph: "♜", tint: .cyan),
        ComposeCustomEmojiCandidate(shortcode: ":saba:", glyph: "🥫", tint: .blue),
        ComposeCustomEmojiCandidate(shortcode: ":fire:", glyph: "🔥", tint: .orange),
        ComposeCustomEmojiCandidate(shortcode: ":phone:", glyph: "▯", tint: .teal),
        ComposeCustomEmojiCandidate(shortcode: ":vlc:", glyph: "🔺", tint: .orange)
    ]

    static let partyParrotValues: [ComposeCustomEmojiCandidate] = [
        ComposeCustomEmojiCandidate(shortcode: ":60fpsparrot:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":angelparrot:", glyph: "🪽", tint: .mint),
        ComposeCustomEmojiCandidate(shortcode: ":partyparrot:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":fastparrot:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":peekparrot:", glyph: "◖", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":rightparrot:", glyph: "◗", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":leftparrot:", glyph: "◔", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":parrotwave:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":beerparrot:", glyph: "🍺", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":gentlemanparrot:", glyph: "🎩", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":pirateparrot:", glyph: "🏴", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":birthdayparrot:", glyph: "🎉", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":blondeparrot:", glyph: "👱", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":confusedparrot:", glyph: "🌀", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":shuffleparrot:", glyph: "🪩", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":sadparrot:", glyph: "🐦", tint: .blue),
        ComposeCustomEmojiCandidate(shortcode: ":brazilparrot:", glyph: "🇧🇷", tint: .green),
        ComposeCustomEmojiCandidate(shortcode: ":christmasparrot:", glyph: "🎅", tint: .red)
    ]
}

private struct ComposeCustomEmojiPicker: View {
    let isContinuousInput: Bool
    let onSelect: (ComposeCustomEmojiCandidate) -> Void
    let onReturn: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(minimum: 30, maximum: 44), spacing: 16), count: 8)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    emojiSection("CUSTOM", values: ComposeCustomEmojiCandidate.customPickerValues)
                    emojiSection("PARTY PARROTS", values: ComposeCustomEmojiCandidate.partyParrotValues)
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, isContinuousInput ? 72 : 24)
            }

            if isContinuousInput {
                Button(action: onReturn) {
                    Image(systemName: "return")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 48)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .accessibilityLabel("Finish emoji input")
                .accessibilityIdentifier("compose.emoji.finish")
            }
        }
        .frame(height: 330)
        .background(Color(white: 0.18))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.32))
                .frame(height: 1)
        }
        .accessibilityLabel("Custom emoji picker")
    }

    private func emojiSection(_ title: String, values: [ComposeCustomEmojiCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(values) { candidate in
                    Button {
                        onSelect(candidate)
                    } label: {
                        ComposeCustomEmojiGridCell(candidate: candidate)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ComposeCustomEmojiGridCell: View {
    let candidate: ComposeCustomEmojiCandidate

    var body: some View {
        ZStack {
            Circle()
                .fill(candidate.tint.opacity(candidate.glyph.count > 2 ? 0.12 : 0.18))

            Text(candidate.glyph)
                .font(.system(size: candidate.glyph.count > 2 ? 12 : 26, weight: .bold, design: .rounded))
                .foregroundStyle(candidate.tint)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel(candidate.shortcode)
    }
}

private struct ComposeCustomEmojiCandidateCell: View {
    let candidate: ComposeCustomEmojiCandidate

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(candidate.tint.opacity(0.18))

                Text(candidate.glyph)
                    .font(.system(size: 22))
            }
            .frame(width: 34, height: 34)

            Text(candidate.shortcode)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 122, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
