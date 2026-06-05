import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
