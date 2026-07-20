import Foundation

@MainActor
final class ComposeFeatureModel: ObservableObject {
    typealias SubmitHandler = @MainActor (
        _ request: ComposeSubmitRequest,
        _ onProgress: @escaping @MainActor @Sendable (
            ComposeSubmissionState
        ) -> Void
    ) async -> Bool

    @Published var context: ComposeContext
    let characterLimit: Int
    @Published var text = ""
    @Published var sensitiveReason = ""
    @Published var isSensitiveReasonVisible = false
    @Published var selectedMediaItems: [ComposeSelectedMedia] = []
    @Published var selectedCustomEmojis: [ComposeCustomEmojiReference] = []
    @Published var activeDraftID: String?
    @Published private(set) var submissionState: ComposeSubmissionState = .editing

    @Published private(set) var isSubmitAvailable: Bool

    init(
        context: ComposeContext,
        isSubmitAvailable: Bool,
        characterLimit: Int = 500
    ) {
        self.context = context
        self.isSubmitAvailable = isSubmitAvailable
        self.characterLimit = characterLimit
    }

    var remainingCharacters: Int {
        characterLimit - text.count
    }

    var canSubmit: Bool {
        isSubmitAvailable
            && !submissionState.isBusy
            && hasContent
            && remainingCharacters >= 0
    }

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedMediaItems.isEmpty
    }

    func enforceCharacterLimit() {
        guard text.count > characterLimit else { return }
        text = String(text.prefix(characterLimit))
    }

    func updateSubmitAvailability(_ isAvailable: Bool) {
        isSubmitAvailable = isAvailable
    }

    func recordCustomEmoji(_ reference: ComposeCustomEmojiReference) {
        guard !selectedCustomEmojis.contains(where: {
            $0.shortcode == reference.shortcode
        }) else { return }
        selectedCustomEmojis.append(reference)
    }

    func resetFailure() {
        if case .failed = submissionState {
            submissionState = .editing
        }
    }

    @discardableResult
    func submit(using handler: SubmitHandler?) async -> Bool {
        guard canSubmit else { return false }
        guard let handler else {
            submissionState = .queued(eventID: nil)
            return true
        }

        submissionState = selectedMediaItems.isEmpty
            ? .signing
            : .uploadingMedia(completed: 0, total: selectedMediaItems.count)
        let didSubmit = await handler(makeRequest()) { [weak self] state in
            self?.submissionState = state
        }
        if !didSubmit {
            submissionState = .failed(
                message: "The post could not be queued. Check the signer, media server, and relay settings."
            )
        } else if submissionState.isBusy {
            submissionState = .queued(eventID: nil)
        }
        return didSubmit
    }

    func makeRequest() -> ComposeSubmitRequest {
        ComposeSubmitRequest(
            context: context,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            isSensitive: isSensitiveReasonVisible,
            sensitiveReason: sensitiveReason.trimmingCharacters(in: .whitespacesAndNewlines),
            customEmojis: selectedCustomEmojis.filter {
                text.contains(":\($0.shortcode):")
            },
            media: selectedMediaItems.compactMap(\.uploadRequest)
        )
    }
}
