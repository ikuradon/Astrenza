import PhotosUI
import SwiftUI

struct ComposeNavigationBar: View {
    let mode: ComposeSheetMode
    let canSubmit: Bool
    let submissionState: ComposeSubmissionState
    let accent: Color
    let onClose: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        ZStack {
            Text(mode.title)
                .font(.astrenza(.point20, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            HStack {
                Button("Close", action: onClose)
                    .font(.astrenza(.point18, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)

                Spacer()

                if submissionState.isBusy {
                    ProgressView()
                        .tint(accent)
                        .frame(minWidth: 50)
                        .accessibilityLabel("Submitting post")
                } else {
                    Button(mode.actionTitle, action: onSubmit)
                        .font(.astrenza(.point18, weight: .heavy, design: .rounded))
                        .foregroundStyle(canSubmit ? accent : Color.secondary.opacity(0.55))
                        .disabled(!canSubmit)
                }
            }
        }
        .padding(.horizontal, AstrenzaSpacing.point20)
        .frame(height: 72)
    }
}

struct ComposeEditorArea: View {
    let mode: ComposeSheetMode
    let account: NostrAccountSummary?
    @Binding var text: String
    @FocusState.Binding var isEditorFocused: Bool
    let selectedMediaItems: [ComposeSelectedMedia]
    @Binding var activeMediaMenuItem: ComposeSelectedMedia?
    @Binding var isUserSwitcherPresented: Bool
    let remainingCharacters: Int

    var body: some View {
        HStack(alignment: .top, spacing: AstrenzaSpacing.point14) {
            userSwitcherButton
            editorStack
            characterCounter
        }
        .padding(.horizontal, AstrenzaSpacing.point18)
    }

    private var userSwitcherButton: some View {
        Button {
            withAnimation(.spring(duration: AstrenzaMotion.emphasized, bounce: 0.2)) {
                isUserSwitcherPresented.toggle()
            }
        } label: {
            UserSwitchButton(
                isExpanded: isUserSwitcherPresented,
                account: account
            )
        }
        .buttonStyle(.plain)
        .padding(.top, AstrenzaSpacing.point18)
        .accessibilityLabel("Switch user")
    }

    private var editorStack: some View {
        VStack(alignment: .leading, spacing: AstrenzaSpacing.point8) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(mode.placeholder)
                        .font(.astrenza(.point18, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.78))
                        .padding(.top, AstrenzaSpacing.point26)
                        .padding(.leading, AstrenzaSpacing.point5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.astrenza(.point19, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isEditorFocused)
                    .padding(.top, AstrenzaSpacing.point16)
                    .padding(.leading, -4)
                    .frame(minHeight: selectedMediaItems.isEmpty ? 320 : 64)
                    .accessibilityLabel(mode.placeholder)
            }

            if !selectedMediaItems.isEmpty {
                ComposeSelectedMediaStrip(items: selectedMediaItems) { media in
                    withAnimation(.spring(duration: AstrenzaMotion.standard, bounce: 0.12)) {
                        activeMediaMenuItem = media
                    }
                }
                .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
                .padding(.leading, AstrenzaSpacing.point2)
            }
        }
    }

    private var characterCounter: some View {
        Text("\(remainingCharacters)")
            .font(.astrenza(.point18, weight: .semibold, design: .rounded))
            .foregroundStyle(remainingCharacters < 0 ? .red : Color.secondary.opacity(0.78))
            .padding(.top, AstrenzaSpacing.point26)
            .frame(width: 48, alignment: .trailing)
    }
}

struct ComposeBottomControls: View {
    @Binding var sensitiveReason: String
    let isSensitiveReasonVisible: Bool
    let isCustomEmojiPickerPresented: Bool
    let isContinuousCustomEmojiInput: Bool
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    let activeCompletion: ComposeCompletion?
    let customEmojiSets: [ComposeCustomEmojiSet]
    let isCustomEmojiResolving: Bool
    let accent: Color
    let onEmojiSelected: (ComposeCustomEmojiCandidate) -> Void
    let onEmojiReturn: () -> Void
    let onCameraRequested: () -> Void
    let onEmojiTap: () -> Void
    let onEmojiLongPress: () -> Void
    let onSensitiveToggle: () -> Void
    let onMentionTap: () -> Void
    let onHashtagTap: () -> Void
    let onSettingsTap: () -> Void
    let onCompletionSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isSensitiveReasonVisible {
                ComposeSensitiveReasonField(sensitiveReason: $sensitiveReason, accent: accent)
                    .padding(.horizontal, AstrenzaSpacing.point14)
                    .padding(.bottom, AstrenzaSpacing.point8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isCustomEmojiPickerPresented {
                ComposeCustomEmojiPicker(
                    isContinuousInput: isContinuousCustomEmojiInput,
                    emojiSets: customEmojiSets,
                    isResolving: isCustomEmojiResolving
                ) { candidate in
                    onEmojiSelected(candidate)
                } onReturn: {
                    onEmojiReturn()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let activeCompletion {
                ComposeCompletionBar(completion: activeCompletion) { value in
                    onCompletionSelected(value)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ComposeToolbar(
                    selectedPhotoItems: $selectedPhotoItems,
                    onCameraRequested: onCameraRequested,
                    onEmojiTap: onEmojiTap,
                    onEmojiLongPress: onEmojiLongPress,
                    onSensitiveToggle: onSensitiveToggle,
                    onMentionTap: onMentionTap,
                    onHashtagTap: onHashtagTap,
                    onSettingsTap: onSettingsTap
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: AstrenzaMotion.standard, bounce: 0.1), value: activeCompletion?.trigger)
        .animation(.spring(duration: AstrenzaMotion.standard, bounce: 0.1), value: isSensitiveReasonVisible)
        .animation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.12), value: isCustomEmojiPickerPresented)
    }
}

private struct ComposeSensitiveReasonField: View {
    @Binding var sensitiveReason: String
    let accent: Color

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.astrenza(.point16, weight: .black))
                .foregroundStyle(accent)

            TextField("Sensitive reason", text: $sensitiveReason)
                .font(.astrenza(.point15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)
                .submitLabel(.done)
        }
        .padding(.horizontal, AstrenzaSpacing.point13)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous)
                .stroke(accent.opacity(0.26), lineWidth: 1)
        }
    }
}

private struct ComposeToolbar: View {
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    let onCameraRequested: () -> Void
    let onEmojiTap: () -> Void
    let onEmojiLongPress: () -> Void
    let onSensitiveToggle: () -> Void
    let onMentionTap: () -> Void
    let onHashtagTap: () -> Void
    let onSettingsTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 8, matching: .images) {
                ComposeToolIcon(systemName: "photo.on.rectangle.angled")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        onCameraRequested()
                    }
            )
            .accessibilityLabel("Add media")

            ComposeEmojiToolButton(
                onTap: onEmojiTap,
                onLongPress: onEmojiLongPress
            )

            ComposeToolButton(systemName: "exclamationmark.triangle", label: "Content warning", action: onSensitiveToggle)
            ComposeToolButton(systemName: "at", label: "Mention", action: onMentionTap)
            ComposeToolButton(systemName: "number", label: "Hashtag", action: onHashtagTap)

            Spacer(minLength: 0)

            Button(action: onSettingsTap) {
                ComposeToolIcon(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Composer settings")
        }
        .padding(.horizontal, AstrenzaSpacing.point14)
        .frame(height: 60)
        .background(Color.black.opacity(0.28))
    }
}
