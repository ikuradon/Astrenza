import SwiftUI

struct FilterEditorSheet: View {
    @State private var draft: FilterEditorDraft
    @State private var searchText = ""
    let onCancel: () -> Void
    let onSave: (FilterEditorDraft) -> Void

    init(draft: FilterEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (FilterEditorDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            SettingsList {
                if draft.kind == .user && draft.selectedUser == nil {
                    userSearchContent
                } else {
                    editorContent
                }
            }
            .settingsNavigation(title: draft.kind.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.astrenzaAccent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(draft)
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(draft.canSave ? Color.astrenzaAccent : .secondary)
                    .disabled(!draft.canSave)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private var userSearchContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .bold))
            TextField("Search People", text: $searchText)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(Color.astrenzaAccent.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        SettingsSection {
            ForEach(filteredCandidates) { candidate in
                Button {
                    draft.selectedUser = candidate
                    draft.value = candidate.id
                    draft.matchingCount = 2
                } label: {
                    FilterCandidateUserRow(candidate: candidate)
                }
                .buttonStyle(.plain)

                if candidate.id != filteredCandidates.last?.id {
                    SettingsDivider()
                        .padding(.leading, 86)
                }
            }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if draft.kind == .user, let selectedUser = draft.selectedUser {
            SettingsSection {
                FilterSelectedUserRow(candidate: selectedUser)
            }
        } else if draft.kind == .keyword || draft.kind == .hashtag {
            SettingsSection {
                TextField(inputPlaceholder, text: $draft.value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 18)
                    .frame(height: 58)
            }
        }

        if draft.kind == .potentialSpam {
            SettingsSection {
                FilterToggleLine(title: "Enabled", subtitle: nil, isOn: $draft.isEnabled)
                SettingsDivider()
                FilterToggleLine(
                    title: "Mask with a Warning",
                    subtitle: "Filtered posts will be hidden behind a warning that you can tap to reveal.",
                    isOn: $draft.masksWithWarning
                )
            }
        } else {
            SettingsSection {
                FilterToggleLine(
                    title: "Mask with a Warning",
                    subtitle: "Filtered posts will be hidden behind a warning that you can tap to reveal.",
                    isOn: $draft.masksWithWarning
                )
            }

            SettingsSection(title: "APPLY TO") {
                ForEach(FilterApplicationScope.allCases) { scope in
                    FilterScopeToggleRow(
                        scope: scope,
                        isOn: Binding(
                            get: { draft.selectedScopes.contains(scope) },
                            set: { isOn in
                                if isOn {
                                    draft.selectedScopes.insert(scope)
                                } else {
                                    draft.selectedScopes.remove(scope)
                                }
                            }
                        )
                    )
                    if scope != FilterApplicationScope.allCases.last {
                        SettingsDivider()
                    }
                }
            }

            SettingsSection(title: "OPTIONS") {
                HStack {
                    Text("Duration")
                    Spacer()
                    Text("Forever")
                        .foregroundStyle(Color.astrenzaAccent)
                }
                .padding(.horizontal, 18)
                .frame(height: 58)
                .settingsRowTextStyle()
            }
        }

        SettingsSection(title: "POSTS") {
            HStack {
                Text("Matching Posts")
                Spacer()
                Text("\(draft.matchingCount)/\(draft.totalCount)")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .settingsChevronStyle()
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .settingsRowTextStyle()
        } footer: {
            "Filtering mentions will not prevent push notifications for those posts."
        }
    }

    private var inputPlaceholder: String {
        switch draft.kind {
        case .hashtag: "Hashtag"
        case .keyword: "Keyword"
        default: ""
        }
    }

    private var filteredCandidates: [FilterCandidateUser] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return FilterCandidateUser.mockCandidates }
        return FilterCandidateUser.mockCandidates.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.nip05.localizedCaseInsensitiveContains(query)
                || $0.npub.localizedCaseInsensitiveContains(query)
        }
    }
}
