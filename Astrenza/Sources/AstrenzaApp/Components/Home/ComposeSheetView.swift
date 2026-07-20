import AstrenzaCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool
    let context: ComposeContext
    let isSubmitAvailable: Bool
    let onSubmit: ComposeFeatureModel.SubmitHandler?
    let accountID: String?
    let eventStore: NostrEventStore?
    let accounts: [NostrAccountSummary]
    let onSelectAccount: (String) -> Void
    @StateObject private var feature: ComposeFeatureModel
    @State private var suggestions: ComposeSuggestionSnapshot
    @State private var isUserSwitcherPresented = false
    @State private var isCameraPresented = false
    @State private var isFileImporterPresented = false
    @State private var isCustomEmojiPickerPresented = false
    @State private var isContinuousCustomEmojiInput = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var activeMediaMenuItem: ComposeSelectedMedia?
    @State private var previewMediaItem: ComposeSelectedMedia?
    @State private var altTextMediaItem: ComposeSelectedMedia?
    @State private var isComposerSettingsPresented = false
    @State private var isDraftCloseDialogPresented = false
    @State private var isDraftsViewPresented = false
    @State private var savedDatabaseDrafts: [ComposeDraft] = []
    @State private var pendingDraftTransfer: ComposeDraftTransfer?
    private let accent = Color.astrenzaAccent

    init(
        context: ComposeContext = .post,
        isSubmitAvailable: Bool = true,
        onSubmit: ComposeFeatureModel.SubmitHandler? = nil,
        accountID: String? = nil,
        eventStore: NostrEventStore? = nil,
        accounts: [NostrAccountSummary] = [],
        onSelectAccount: @escaping (String) -> Void = { _ in }
    ) {
        self.context = context
        self.isSubmitAvailable = isSubmitAvailable
        self.onSubmit = onSubmit
        self.accountID = accountID
        self.eventStore = eventStore
        self.accounts = accounts
        self.onSelectAccount = onSelectAccount
        _feature = StateObject(wrappedValue: ComposeFeatureModel(
            context: context,
            isSubmitAvailable: isSubmitAvailable
        ))
        _suggestions = State(
            initialValue: accountID == nil ? .preview : .empty
        )
    }

    private var mode: ComposeSheetMode {
        feature.context.mode
    }

    private var remainingCharacters: Int {
        feature.remainingCharacters
    }

    private var selectedAccountSummary: NostrAccountSummary? {
        accounts.first { $0.id == accountID }
    }

    private var suggestionLoadIdentity: String {
        "\(accountID ?? "preview"):\(eventStore == nil ? "missing" : "available")"
    }

    private var autosaveIdentity: String {
        let media = feature.selectedMediaItems.map {
            "\($0.id.uuidString):\($0.altText ?? "")"
        }.joined(separator: "|")
        return [
            accountID ?? "preview",
            feature.text,
            feature.sensitiveReason,
            feature.isSensitiveReasonVisible.description,
            media
        ].joined(separator: "\u{1f}")
    }

    private var submissionFailureMessage: String {
        guard case .failed(let message) = feature.submissionState else {
            return ""
        }
        return message
    }

    private var isSubmissionFailurePresented: Binding<Bool> {
        Binding(
            get: {
                if case .failed = feature.submissionState { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { feature.resetFailure() }
            }
        )
    }

    private func loadLiveSuggestions() async {
        guard accountID != nil, let eventStore else { return }
        let source = await Task.detached(priority: .userInitiated) {
            ComposeSuggestionSnapshot.source(eventStore: eventStore)
        }.value
        guard !Task.isCancelled else { return }
        suggestions = ComposeSuggestionSnapshot.project(
            profiles: source.profiles,
            recentNotes: source.recentNotes
        )
    }

    private var hasDraftContent: Bool {
        feature.hasContent
    }

    private var savedDrafts: [ComposeDraft] {
        savedDatabaseDrafts
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
                        withAnimation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.14)) {
                            isUserSwitcherPresented = false
                        }
                    }

                UserSwitcherMenu(
                    accounts: accounts,
                    onSelectAccount: selectAccount,
                    onSettingsTap: {
                        withAnimation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.14)) {
                            isUserSwitcherPresented = false
                        }
                    }
                )
                .padding(.leading, AstrenzaSpacing.point18)
                .padding(.top, 154)
                .transition(.scale(scale: 0.72, anchor: .topLeading).combined(with: .opacity))
                .zIndex(20)
            }

            if let media = activeMediaMenuItem {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: AstrenzaMotion.standard, bounce: 0.12)) {
                            activeMediaMenuItem = nil
                        }
                    }

                ComposeMediaActionMenu(
                    onPreview: {
                        previewMediaItem = media
                        activeMediaMenuItem = nil
                    },
                    onAddDescription: {
                        altTextMediaItem = media
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
                        withAnimation(.spring(duration: AstrenzaMotion.standard, bounce: 0.12)) {
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomComposerControls
        }
        .composeSheetPresentations(
            isCameraPresented: $isCameraPresented,
            isFileImporterPresented: $isFileImporterPresented,
            isDraftCloseDialogPresented: $isDraftCloseDialogPresented,
            isDraftsViewPresented: $isDraftsViewPresented,
            savedDrafts: savedDrafts,
            onIgnoreDraft: ignoreCurrentDraft,
            onSaveDraft: saveCurrentDraft,
            onDeleteDrafts: deleteDrafts,
            onSelectDraft: restoreDraft,
            onCameraImage: addCameraImage,
            onImportFiles: importFiles
        )
        .sheet(item: $previewMediaItem) { media in
            ComposeMediaPreviewView(media: media)
        }
        .sheet(item: $altTextMediaItem) { media in
            ComposeMediaAltTextEditor(media: media) { altText in
                updateAltText(altText, for: media)
            }
            .presentationDetents([.large])
        }
        .alert(
            "Post Not Sent",
            isPresented: isSubmissionFailurePresented
        ) {
            Button("OK") { feature.resetFailure() }
        } message: {
            Text(submissionFailureMessage)
        }
        .onAppear {
            reloadDrafts()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                isEditorFocused = true
            }
        }
        .task(id: suggestionLoadIdentity) {
            await loadLiveSuggestions()
        }
        .task(id: autosaveIdentity) {
            guard accountID != nil, eventStore != nil else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            autosaveCurrentDraft()
        }
        .onChange(of: feature.text) { _, _ in
            feature.enforceCharacterLimit()
            feature.resetFailure()
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            loadSelectedPhotos(newItems)
        }
        .onChange(of: accountID) { _, newAccountID in
            transferDraftIfNeeded(to: newAccountID)
            reloadDrafts()
        }
        .onChange(of: isSubmitAvailable) { _, isAvailable in
            feature.updateSubmitAvailability(isAvailable)
        }
    }

    private var navigationBar: some View {
        ComposeNavigationBar(
            mode: mode,
            canSubmit: feature.canSubmit,
            submissionState: feature.submissionState,
            accent: accent,
            onClose: closeComposer,
            onSubmit: submitComposer
        )
    }

    private var editorArea: some View {
        ComposeEditorArea(
            mode: mode,
            account: selectedAccountSummary,
            text: $feature.text,
            isEditorFocused: $isEditorFocused,
            selectedMediaItems: feature.selectedMediaItems,
            activeMediaMenuItem: $activeMediaMenuItem,
            isUserSwitcherPresented: $isUserSwitcherPresented,
            remainingCharacters: remainingCharacters
        )
    }

    @ViewBuilder
    private var bottomComposerControls: some View {
        ComposeBottomControls(
            sensitiveReason: $feature.sensitiveReason,
            isSensitiveReasonVisible: feature.isSensitiveReasonVisible,
            isCustomEmojiPickerPresented: isCustomEmojiPickerPresented,
            isContinuousCustomEmojiInput: isContinuousCustomEmojiInput,
            selectedPhotoItems: $selectedPhotoItems,
            activeCompletion: activeCompletion,
            customEmojiCandidates: suggestions.pickerEmojis,
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
        guard feature.text.last?.isWhitespace != true else { return nil }
        guard let token = feature.text.split(whereSeparator: \.isWhitespace).last else { return nil }
        guard let trigger = token.first, ["@", "#", ":"].contains(trigger) else { return nil }
        let query = String(token.dropFirst()).lowercased()

        switch trigger {
        case "@":
            return ComposeCompletion(
                trigger: "@",
                mentionCandidates: suggestions.mentions
                    .filter { !query.isEmpty && $0.searchText.contains(query) }
            )
        case "#":
            return ComposeCompletion(
                trigger: "#",
                hashtagCandidates: suggestions.hashtags
                    .filter { query.isEmpty || $0.tag.lowercased().contains(query) }
            )
        case ":":
            return ComposeCompletion(
                trigger: ":",
                customEmojiCandidates: suggestions.completionEmojis
                    .filter { !query.isEmpty && $0.shortcode.lowercased().contains(query) }
            )
        default:
            return nil
        }
    }

    private func insertTrigger(_ trigger: String) {
        if !feature.text.isEmpty && !feature.text.last!.isWhitespace {
            feature.text += " "
        }
        feature.text += trigger
        isEditorFocused = true
    }

    private func insertCompletion(_ value: String) {
        if let candidate = suggestions.completionEmojis.first(where: {
            $0.shortcode == value
        }) {
            recordCustomEmoji(candidate)
        }
        let parts = feature.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let last = parts.last, ["@", "#", ":"].contains(last.first ?? " ") else {
            insertTrigger(value)
            return
        }

        feature.text.removeLast(last.count)
        feature.text += "\(value) "
        isEditorFocused = true
    }

    private func insertStandaloneToken(_ value: String) {
        if !feature.text.isEmpty && !feature.text.last!.isWhitespace {
            feature.text += " "
        }
        feature.text += "\(value) "
        isEditorFocused = true
    }

    private func insertContinuousCustomEmoji(_ value: String) {
        if !feature.text.isEmpty && !feature.text.last!.isWhitespace {
            feature.text += "\u{200B}"
        }
        feature.text += value
    }

    private func handleCustomEmojiSelection(_ candidate: ComposeCustomEmojiCandidate) {
        recordCustomEmoji(candidate)
        if isContinuousCustomEmojiInput {
            insertContinuousCustomEmoji(candidate.shortcode)
        } else {
            insertStandaloneToken(candidate.shortcode)
            withAnimation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.12)) {
                isCustomEmojiPickerPresented = false
            }
        }
    }

    private func recordCustomEmoji(_ candidate: ComposeCustomEmojiCandidate) {
        let shortcode = candidate.shortcode.trimmingCharacters(
            in: CharacterSet(charactersIn: ":")
        )
        if let imageURL = candidate.imageURL,
           !feature.selectedCustomEmojis.contains(where: { $0.shortcode == shortcode }) {
            feature.recordCustomEmoji(ComposeCustomEmojiReference(
                shortcode: shortcode,
                url: imageURL.absoluteString
            ))
        }
    }

    private func presentCustomEmojiPicker(isContinuous: Bool) {
        isEditorFocused = false
        isContinuousCustomEmojiInput = isContinuous
        withAnimation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.12)) {
            isCustomEmojiPickerPresented = true
        }
    }

    private func toggleSensitiveReason() {
        isCustomEmojiPickerPresented = false
        isContinuousCustomEmojiInput = false
        feature.isSensitiveReasonVisible.toggle()
    }

    private func toggleComposerSettings() {
        withAnimation(.spring(duration: AstrenzaMotion.standard, bounce: 0.12)) {
            isComposerSettingsPresented.toggle()
        }
    }

    private func finishContinuousCustomEmojiInput() {
        if !feature.text.isEmpty && !feature.text.last!.isWhitespace {
            feature.text += " "
        }
        isContinuousCustomEmojiInput = false
        withAnimation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.12)) {
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
                let contentType = item.supportedContentTypes.first ?? .jpeg
                if let media = await persistedMedia(
                    data: data,
                    image: image,
                    mimeType: contentType.preferredMIMEType ?? "image/jpeg",
                    fileExtension: contentType.preferredFilenameExtension ?? "jpg"
                ) {
                    loadedItems.append(media)
                }
            }
            await MainActor.run {
                feature.selectedMediaItems.append(contentsOf: loadedItems)
                selectedPhotoItems = []
            }
        }
    }

    private func updateAltText(
        _ altText: String,
        for media: ComposeSelectedMedia
    ) {
        guard let index = feature.selectedMediaItems.firstIndex(where: { $0.id == media.id }) else { return }
        feature.selectedMediaItems[index].altText = altText.isEmpty ? nil : altText
    }

    private func removeMedia(_ media: ComposeSelectedMedia) {
        feature.selectedMediaItems.removeAll { $0.id == media.id }
        if let localURL = media.localURL {
            try? ComposeMediaFileStore().remove(localURL)
        }
    }

    private func deleteLocalMediaFiles() {
        guard let store = try? ComposeMediaFileStore() else { return }
        for media in feature.selectedMediaItems {
            if let localURL = media.localURL {
                store.remove(localURL)
            }
        }
    }

    private func addCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        Task {
            if let media = await persistedMedia(
                data: data,
                image: image,
                mimeType: "image/jpeg",
                fileExtension: "jpg"
            ) {
                feature.selectedMediaItems.append(media)
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        Task {
            for url in urls {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else { continue }
                let contentType = (try? url.resourceValues(
                    forKeys: [.contentTypeKey]
                ))?.contentType ?? UTType.image
                if let media = await persistedMedia(
                    data: data,
                    image: image,
                    mimeType: contentType.preferredMIMEType ?? "image/jpeg",
                    fileExtension: contentType.preferredFilenameExtension
                        ?? url.pathExtension
                ) {
                    feature.selectedMediaItems.append(media)
                }
            }
        }
    }

    private func persistedMedia(
        data: Data,
        image: UIImage,
        mimeType: String,
        fileExtension: String
    ) async -> ComposeSelectedMedia? {
        let id = UUID()
        let localURL = try? await Task.detached(priority: .userInitiated) {
            try ComposeMediaFileStore().persist(
                data: data,
                id: id,
                fileExtension: fileExtension
            )
        }.value
        guard let localURL else { return nil }
        return ComposeSelectedMedia(
            id: id,
            image: image,
            localURL: localURL,
            mimeType: mimeType,
            altText: nil
        )
    }

    private func closeComposer() {
        if hasDraftContent {
            isDraftCloseDialogPresented = true
        } else {
            dismiss()
        }
    }

    private func submitComposer() {
        guard feature.canSubmit else { return }
        Task {
            let didSubmit = await feature.submit(using: onSubmit)
            if didSubmit {
                deleteActiveDatabaseDraftIfNeeded()
                deleteLocalMediaFiles()
                dismiss()
            }
        }
    }

    private func saveCurrentDraft() {
        guard accountID != nil, eventStore != nil else {
            isDraftCloseDialogPresented = false
            dismiss()
            return
        }

        saveDatabaseDraft()
        isDraftCloseDialogPresented = false
        dismiss()
    }

    private func autosaveCurrentDraft() {
        guard feature.hasContent else { return }
        saveDatabaseDraft()
    }

    private func saveDatabaseDraft() {
        guard let accountID, let eventStore else { return }
        let draftID = feature.activeDraftID ?? UUID().uuidString
        let warning = feature.isSensitiveReasonVisible
            ? feature.sensitiveReason.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let media = feature.selectedMediaItems.map { item in
            let upload = item.uploadRequest
            return NostrDraftMediaReference(
                id: item.id.uuidString,
                kind: "photo",
                localIdentifier: nil,
                localPath: item.localURL?.path,
                mimeType: item.mimeType,
                width: upload?.width,
                height: upload?.height,
                altText: item.altText,
                uploadState: .local
            )
        }
        try? eventStore.saveDraft(NostrDraftRecord(
            draftID: draftID,
            accountID: accountID,
            context: feature.context.draftContext,
            text: feature.text,
            contentWarning: warning.isEmpty ? nil : warning,
            tags: feature.selectedCustomEmojis.map {
                ["emoji", $0.shortcode, $0.url]
            },
            media: media,
            updatedAt: Int(Date().timeIntervalSince1970)
        ))
        feature.activeDraftID = draftID
        reloadDrafts()
    }

    private func deleteActiveDatabaseDraftIfNeeded() {
        guard let accountID, let eventStore, let activeDraftID = feature.activeDraftID else { return }
        try? eventStore.deleteDraft(accountID: accountID, draftID: activeDraftID)
        feature.activeDraftID = nil
        reloadDrafts()
    }

    private func ignoreCurrentDraft() {
        deleteActiveDatabaseDraftIfNeeded()
        dismiss()
    }

    private func deleteDrafts(at offsets: IndexSet) {
        guard let accountID, let eventStore else { return }
        let ids = offsets.map { savedDrafts[$0].id }
        try? eventStore.deleteDrafts(accountID: accountID, draftIDs: ids)
        if let activeDraftID = feature.activeDraftID, ids.contains(activeDraftID) {
            feature.activeDraftID = nil
        }
        reloadDrafts()
    }

    private func restoreDraft(_ draft: ComposeDraft) {
        feature.activeDraftID = draft.id
        feature.context = draft.context
        feature.text = draft.text
        if let contentWarning = draft.contentWarning, !contentWarning.isEmpty {
            feature.sensitiveReason = contentWarning
            feature.isSensitiveReasonVisible = true
        } else {
            feature.sensitiveReason = ""
            feature.isSensitiveReasonVisible = false
        }
        feature.selectedCustomEmojis = draft.tags.compactMap { tag in
            guard tag.count >= 3, tag[0] == "emoji" else { return nil }
            return ComposeCustomEmojiReference(shortcode: tag[1], url: tag[2])
        }
        feature.selectedMediaItems = draft.mediaReferences.compactMap { reference in
            guard let path = reference.localPath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = UIImage(data: data)
            else { return nil }
            return ComposeSelectedMedia(
                id: UUID(uuidString: reference.id) ?? UUID(),
                image: image,
                localURL: URL(fileURLWithPath: path),
                mimeType: reference.mimeType ?? "image/jpeg",
                altText: reference.altText
            )
        }
        isDraftsViewPresented = false
        isEditorFocused = true
    }

    private func reloadDrafts() {
        guard let accountID, let eventStore else { return }
        let records = (try? eventStore.drafts(accountID: accountID)) ?? []
        savedDatabaseDrafts = records.map(ComposeDraft.init(record:))
    }

    private func selectAccount(_ pubkey: String) {
        guard pubkey != accountID else {
            isUserSwitcherPresented = false
            return
        }
        autosaveCurrentDraft()
        if let accountID, let draftID = feature.activeDraftID {
            pendingDraftTransfer = ComposeDraftTransfer(
                sourceAccountID: accountID,
                draftID: draftID
            )
        }
        onSelectAccount(pubkey)
        withAnimation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.14)) {
            isUserSwitcherPresented = false
        }
    }

    private func transferDraftIfNeeded(to newAccountID: String?) {
        guard let transfer = pendingDraftTransfer,
              let newAccountID,
              newAccountID != transfer.sourceAccountID,
              let eventStore
        else { return }
        feature.activeDraftID = transfer.draftID
        saveDatabaseDraft()
        try? eventStore.deleteDraft(
            accountID: transfer.sourceAccountID,
            draftID: transfer.draftID
        )
        pendingDraftTransfer = nil
    }

}

private struct ComposeDraftTransfer: Equatable {
    let sourceAccountID: String
    let draftID: String
}

private extension ComposeContext {
    var draftContext: NostrDraftContext {
        switch self {
        case .post:
            .post
        case .reply(let context):
            .reply(
                root: context.root.draftReference,
                parent: context.parent.draftReference,
                recipientPubkeys: context.recipientPubkeys
            )
        case .quote(let context):
            .quote(target: context.target.draftReference)
        }
    }
}

private extension ComposeEventReference {
    var draftReference: NostrDraftEventReference {
        NostrDraftEventReference(
            eventID: eventID,
            relayHint: relayHint,
            pubkey: pubkey
        )
    }
}
