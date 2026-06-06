import AstrenzaCore
import SwiftUI

struct NostrListSettingsView: View {
    let accountID: String?
    let eventStore: NostrEventStore?
    @State private var summaries: [NostrListSummary] = []
    @State private var itemsByListID: [String: [NostrListItemRecord]] = [:]
    @State private var localBookmarkCount = 0
    @State private var localRules: [NostrFilterRuleRecord] = []
    @State private var editorDraft: FilterEditorDraft?
    @State private var isEditingFilters = false
    @State private var loadError: String?

    var body: some View {
        SettingsList {
            SettingsSection(title: "USERS") {
                if accountID == nil || eventStore == nil {
                    NostrListEmptyRow(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "No live account",
                        subtitle: "Filters are scoped to the selected Nostr identity."
                    )
                } else {
                    ForEach(rules(for: .mutedPubkey), id: \.ruleID) { rule in
                        FilterOverviewRuleRow(
                            rule: rule,
                            icon: "person.crop.circle.fill",
                            isEditing: isEditingFilters,
                            onEdit: { editorDraft = draft(for: rule) },
                            onDelete: { delete(rule) }
                        )
                    }
                    if !rules(for: .mutedPubkey).isEmpty {
                        SettingsDivider()
                    }
                    FilterAddButton(title: "Add User") {
                        editorDraft = newDraft(.newUser(accountID: accountID ?? ""))
                    }
                }
            }

            SettingsSection(title: "KEYWORDS") {
                ForEach(rules(for: .keyword), id: \.ruleID) { rule in
                    FilterOverviewRuleRow(
                        rule: rule,
                        icon: "text.quote",
                        isEditing: isEditingFilters,
                        onEdit: { editorDraft = draft(for: rule) },
                        onDelete: { delete(rule) }
                    )
                }
                if !rules(for: .keyword).isEmpty {
                    SettingsDivider()
                }
                FilterAddButton(title: "Add Keyword") {
                    editorDraft = newDraft(.newKeyword(accountID: accountID ?? ""))
                }
            }

            SettingsSection(title: "HASHTAGS") {
                ForEach(rules(for: .mutedHashtag), id: \.ruleID) { rule in
                    FilterOverviewRuleRow(
                        rule: rule,
                        icon: "number",
                        isEditing: isEditingFilters,
                        onEdit: { editorDraft = draft(for: rule) },
                        onDelete: { delete(rule) }
                    )
                }
                if !rules(for: .mutedHashtag).isEmpty {
                    SettingsDivider()
                }
                FilterAddButton(title: "Add Hashtag") {
                    editorDraft = newDraft(.newHashtag(accountID: accountID ?? ""))
                }
            }

            SettingsSection(title: "CUSTOM") {
                Button {
                    editorDraft = potentialSpamDraft()
                } label: {
                    HStack {
                        Text("Potential Spam")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                        Spacer()
                        Text(potentialSpamRule?.isEnabled == true ? "Enabled" : "Disabled")
                            .foregroundStyle(Color.astrenzaAccent)
                    }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .settingsRowTextStyle()
            } footer: {
                "By default, filters are applied to your Home timeline and lists. Mentions can be included from keyword-style filters."
            }

            SettingsSection(title: "LOCAL STATE") {
                NostrLocalStateRow(
                    icon: "bookmark.fill",
                    title: "Local Bookmarks",
                    value: localBookmarkCount,
                    tint: .purple
                )
            } footer: {
                "Local rules are applied immediately. Cached NIP-51 public lists are merged into the same timeline filter pass."
            }

            SettingsSection(title: "NIP-51 LISTS") {
                if accountID == nil || eventStore == nil {
                    NostrListEmptyRow(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "No live account",
                        subtitle: "Log in with npub/NIP-05 to read cached mute, bookmark, relay, and follow-set events."
                    )
                } else if let loadError {
                    NostrListEmptyRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Could not load cached lists",
                        subtitle: loadError
                    )
                } else if summaries.isEmpty {
                    NostrListEmptyRow(
                        icon: "tray.fill",
                        title: "No cached list events",
                        subtitle: "When kind:10000, 10003, 10007, 30000, 30002, or 30003 events are received, they will appear here."
                    )
                } else {
                    ForEach(summaries, id: \.listID) { summary in
                        NostrListSummaryRow(
                            summary: summary,
                            items: itemsByListID[summary.listID] ?? []
                        )
                    }
                }
            } footer: {
                "This is read-only for now. Private encrypted content is cached as an opaque payload until signer-backed decryption is added."
            }
        }
        .settingsNavigation(title: "Filters")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditingFilters ? "Done" : "Edit") {
                    withAnimation(.snappy(duration: 0.18)) {
                        isEditingFilters.toggle()
                    }
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.astrenzaAccent)
                .disabled(accountID == nil || eventStore == nil)
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $editorDraft) { draft in
            FilterEditorSheet(
                draft: draft,
                onCancel: { editorDraft = nil },
                onSave: saveFilterDraft
            )
        }
    }

    private func reload() {
        guard let accountID, let eventStore else {
            summaries = []
            itemsByListID = [:]
            localBookmarkCount = 0
            localRules = []
            loadError = nil
            return
        }

        do {
            let loadedSummaries = try eventStore.listSummaries(accountID: accountID)
            summaries = loadedSummaries
            itemsByListID = Dictionary(
                uniqueKeysWithValues: try loadedSummaries.map { summary in
                    (summary.listID, try eventStore.listItems(listID: summary.listID))
                }
            )
            localRules = try eventStore.filterRules(accountID: accountID)
            localBookmarkCount = try eventStore.localBookmarks(accountID: accountID).count
            loadError = nil
        } catch {
            summaries = []
            itemsByListID = [:]
            localBookmarkCount = 0
            localRules = []
            loadError = error.localizedDescription
        }
    }

    private func rules(for kind: NostrFilterRuleKind) -> [NostrFilterRuleRecord] {
        localRules.filter { $0.kind == kind && !$0.ruleID.hasPrefix(FilterEditorDraft.potentialSpamRuleIDPrefix) }
    }

    private var potentialSpamRule: NostrFilterRuleRecord? {
        localRules.first { $0.ruleID.hasPrefix(FilterEditorDraft.potentialSpamRuleIDPrefix) }
    }

    private func draft(for rule: NostrFilterRuleRecord) -> FilterEditorDraft {
        FilterEditorDraft.existing(
            rule: rule,
            matchingCount: matchingCount(for: rule),
            totalCount: totalCachedPostCount()
        )
    }

    private func potentialSpamDraft() -> FilterEditorDraft {
        let draft = FilterEditorDraft.potentialSpam(
            accountID: accountID ?? "",
            existing: potentialSpamRule,
            matchingCount: potentialSpamRule.map(matchingCount(for:)) ?? 0,
            totalCount: totalCachedPostCount()
        )
        return draft
    }

    private func newDraft(_ draft: FilterEditorDraft) -> FilterEditorDraft {
        var draft = draft
        draft.totalCount = totalCachedPostCount()
        return draft
    }

    private func matchingCount(for rule: NostrFilterRuleRecord) -> Int {
        guard let accountID, let eventStore else { return 0 }
        return (try? eventStore.filterRuleMatchingCount(
            accountID: accountID,
            rule: rule,
            timeline: .home
        )) ?? 0
    }

    private func totalCachedPostCount() -> Int {
        guard let eventStore else { return 0 }
        return ((try? eventStore.events(kind: 1, limit: 10_000).count) ?? 0)
    }

    private func saveFilterDraft(_ draft: FilterEditorDraft) {
        guard let eventStore, let accountID else {
            editorDraft = nil
            return
        }

        do {
            try eventStore.saveFilterRule(draft.rule(accountID: accountID, now: Int(Date().timeIntervalSince1970)))
            reload()
            editorDraft = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ rule: NostrFilterRuleRecord) {
        guard let eventStore, let accountID else { return }
        do {
            try eventStore.deleteFilterRule(accountID: accountID, ruleID: rule.ruleID)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
