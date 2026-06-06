import SwiftUI

struct FilterEditorSheet: View {
    @State private var draft: FilterEditorDraft
    @State private var searchText = ""
    let candidateUsers: [FilterCandidateUser]
    let onCancel: () -> Void
    let onShowMatchingPosts: (FilterEditorDraft) -> Void
    let onSave: (FilterEditorDraft) -> Void

    init(
        draft: FilterEditorDraft,
        candidateUsers: [FilterCandidateUser],
        onCancel: @escaping () -> Void,
        onShowMatchingPosts: @escaping (FilterEditorDraft) -> Void,
        onSave: @escaping (FilterEditorDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.candidateUsers = candidateUsers
        self.onCancel = onCancel
        self.onShowMatchingPosts = onShowMatchingPosts
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
                    draft.matchingCount = 0
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
                Menu {
                    ForEach(FilterDuration.allCases) { duration in
                        Button {
                            draft.duration = duration
                        } label: {
                            if draft.duration == duration {
                                Label(duration.rawValue, systemImage: "checkmark")
                            } else {
                                Text(duration.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(draft.duration.rawValue)
                            .foregroundStyle(Color.astrenzaAccent)
                        Image(systemName: "chevron.right")
                            .settingsChevronStyle()
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                    .settingsRowTextStyle()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        SettingsSection(title: "POSTS") {
            Button {
                onShowMatchingPosts(draft)
            } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        let baseCandidates = candidateUsers.isEmpty ? FilterCandidateUser.mockCandidates : candidateUsers
        guard !query.isEmpty else { return baseCandidates }
        var candidates = baseCandidates.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.nip05.localizedCaseInsensitiveContains(query)
                || $0.npub.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
        if let directCandidate = FilterCandidateUser.directCandidate(from: query),
           !candidates.contains(where: { $0.id == directCandidate.id }) {
            candidates.append(directCandidate)
        }
        return candidates
    }
}
