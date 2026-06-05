import PhotosUI
import SwiftUI
import UIKit

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
        .composeSheetPresentations(
            isCameraPresented: $isCameraPresented,
            isFileImporterPresented: $isFileImporterPresented,
            isDraftCloseDialogPresented: $isDraftCloseDialogPresented,
            isDraftsViewPresented: $isDraftsViewPresented,
            savedDrafts: savedDrafts,
            onIgnoreDraft: { dismiss() },
            onSaveDraft: saveCurrentDraft,
            onDeleteDrafts: { _ in deleteSavedDraft() },
            onSelectDraft: restoreDraft
        )
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
        ComposeNavigationBar(
            mode: mode,
            canSubmit: canSubmit,
            accent: accent,
            onClose: closeComposer,
            onSubmit: { dismiss() }
        )
    }

    private var editorArea: some View {
        ComposeEditorArea(
            mode: mode,
            text: $text,
            isEditorFocused: $isEditorFocused,
            selectedMediaItems: selectedMediaItems,
            activeMediaMenuItem: $activeMediaMenuItem,
            isUserSwitcherPresented: $isUserSwitcherPresented,
            remainingCharacters: remainingCharacters
        )
    }

    @ViewBuilder
    private var bottomComposerControls: some View {
        ComposeBottomControls(
            sensitiveReason: $sensitiveReason,
            isSensitiveReasonVisible: isSensitiveReasonVisible,
            isCustomEmojiPickerPresented: isCustomEmojiPickerPresented,
            isContinuousCustomEmojiInput: isContinuousCustomEmojiInput,
            selectedPhotoItems: $selectedPhotoItems,
            activeCompletion: activeCompletion,
            accent: accent,
            onEmojiSelected: handleCustomEmojiSelection,
            onEmojiReturn: finishContinuousCustomEmojiInput,
            onCameraRequested: { isCameraPresented = true },
            onEmojiTap: { presentCustomEmojiPicker(isContinuous: false) },
            onEmojiLongPress: { presentCustomEmojiPicker(isContinuous: true) },
            onSensitiveToggle: toggleSensitiveReason,
            onMentionTap: { insertTrigger("@") },
            onHashtagTap: { insertTrigger("#") },
            onSettingsTap: toggleComposerSettings,
            onCompletionSelected: insertCompletion
        )
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

    private func handleCustomEmojiSelection(_ candidate: ComposeCustomEmojiCandidate) {
        if isContinuousCustomEmojiInput {
            insertContinuousCustomEmoji(candidate.shortcode)
        } else {
            insertStandaloneToken(candidate.shortcode)
            withAnimation(.spring(duration: 0.24, bounce: 0.12)) {
                isCustomEmojiPickerPresented = false
            }
        }
    }

    private func presentCustomEmojiPicker(isContinuous: Bool) {
        isEditorFocused = false
        isContinuousCustomEmojiInput = isContinuous
        withAnimation(.spring(duration: 0.24, bounce: 0.12)) {
            isCustomEmojiPickerPresented = true
        }
    }

    private func toggleSensitiveReason() {
        isCustomEmojiPickerPresented = false
        isContinuousCustomEmojiInput = false
        isSensitiveReasonVisible.toggle()
    }

    private func toggleComposerSettings() {
        withAnimation(.spring(duration: 0.22, bounce: 0.12)) {
            isComposerSettingsPresented.toggle()
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

    private func restoreDraft(_ draft: ComposeDraft) {
        text = draft.text
        isDraftsViewPresented = false
        isEditorFocused = true
    }

}
