import AstrenzaCore
import SwiftUI

struct TimelineSwipeSettings {
    var longLeftSwipe = "View Detail"
    var longRightSwipe = "Reply"
    var shortLeftSwipe = "No Action"
    var shortRightSwipe = "Favorite"
}

struct SettingsView: View {
    let onClose: () -> Void
    let accountID: String?
    let eventStore: NostrEventStore?
    @Binding var swipeSettings: TimelineSwipeSettings
    @State private var isSoundsEnabled = true
    @State private var isHapticsEnabled = true
    @State private var isTapToTopEnabled = true
    @State private var isIgnoringContentWarnings = false
    @State private var isShowingSensitiveMedia = false
    @State private var areEnhancedCardPreviewsEnabled = false
    @State private var isContextMenuOrderFixed = false
    @State private var areServerTranslationsPrioritized = false
    @State private var isDragAndDropEnabled = true
    @State private var areMentionsUnreadOnly = false
    @State private var isThemeSwipeEnabled = true
    @State private var selectedFont = "San Francisco Rounded"
    @State private var selectedNameLayout = "Both (Vertical)"
    @State private var selectedActionButtons = "Small"
    @State private var textScale = 0.2
    @State private var usesSystemTextSize = true

    init(
        onClose: @escaping () -> Void,
        swipeSettings: Binding<TimelineSwipeSettings>,
        accountID: String? = nil,
        eventStore: NostrEventStore? = nil
    ) {
        self.onClose = onClose
        _swipeSettings = swipeSettings
        self.accountID = accountID
        self.eventStore = eventStore
    }

    var body: some View {
        NavigationStack {
            SettingsList {
                SettingsSection(title: "ACCOUNTS") {
                    SettingsAccountRow(
                        title: "User Alpha",
                        subtitle: "alpha@mock.example",
                        avatarStyle: AvatarStyle(primary: .black, secondary: .cyan, symbolName: "cat.fill"),
                        accountID: accountID,
                        eventStore: eventStore
                    )
                    SettingsAccountRow(
                        title: "User Beta",
                        subtitle: "beta@mock.example",
                        avatarStyle: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "moon.stars.fill"),
                        accountID: nil,
                        eventStore: nil
                    )
                    SettingsNavigationRow(title: "Add Account", icon: "plus", tint: .green) {
                        OnboardingView()
                    }
                }

                SettingsSection(title: "GENERAL") {
                    SettingsNavigationRow(title: "Display", icon: "plus.forwardslash.minus", tint: .gray) {
                        DisplaySettingsView(
                            selectedFont: $selectedFont,
                            selectedNameLayout: $selectedNameLayout,
                            selectedActionButtons: $selectedActionButtons,
                            textScale: $textScale,
                            usesSystemTextSize: $usesSystemTextSize
                        )
                    }
                    SettingsNavigationRow(title: "Behaviors", icon: "point.3.connected.trianglepath.dotted", tint: .orange) {
                        BehaviorsSettingsView(
                            isTapToTopEnabled: $isTapToTopEnabled,
                            isIgnoringContentWarnings: $isIgnoringContentWarnings,
                            isShowingSensitiveMedia: $isShowingSensitiveMedia,
                            areEnhancedCardPreviewsEnabled: $areEnhancedCardPreviewsEnabled,
                            isContextMenuOrderFixed: $isContextMenuOrderFixed,
                            areServerTranslationsPrioritized: $areServerTranslationsPrioritized,
                            isDragAndDropEnabled: $isDragAndDropEnabled,
                            areMentionsUnreadOnly: $areMentionsUnreadOnly
                        )
                    }
                    SettingsNavigationRow(title: "Gestures", icon: "switch.2", tint: .blue) {
                        GesturesSettingsView(
                            longLeftSwipe: $swipeSettings.longLeftSwipe,
                            longRightSwipe: $swipeSettings.longRightSwipe,
                            shortLeftSwipe: $swipeSettings.shortLeftSwipe,
                            shortRightSwipe: $swipeSettings.shortRightSwipe,
                            isThemeSwipeEnabled: $isThemeSwipeEnabled
                        )
                    }
                    SettingsNavigationRow(title: "Notifications", icon: "bell.fill", tint: .purple) {
                        EmptySettingsDestination(title: "Notifications")
                    }
                    SettingsToggleRow(title: "Sounds", icon: "speaker.wave.2.fill", tint: .brown, isOn: $isSoundsEnabled)
                    SettingsToggleRow(title: "Haptics", icon: "circle.dotted.circle", tint: .gray, isOn: $isHapticsEnabled)
                    SettingsValueNavigationRow(title: "Browser", value: "Astrenza", icon: "safari.fill", tint: .cyan) {
                        EmptySettingsDestination(title: "Browser")
                    }
                    SettingsValueNavigationRow(title: "App Icon", value: "Default", icon: "app.dashed", tint: .indigo) {
                        EmptySettingsDestination(title: "App Icon")
                    }
                }

                SettingsSection(title: "ABOUT") {
                    SettingsNavigationRow(title: "Free Trial", icon: "checkmark.seal.fill", tint: .purple) {
                        EmptySettingsDestination(title: "Free Trial")
                    }
                    SettingsStatusNavigationRow(title: "Sync Status", statusColor: .green, icon: "icloud.fill", tint: .gray) {
                        EmptySettingsDestination(title: "Sync Status")
                    }
                    SettingsNavigationRow(title: "Support", icon: "lifepreserver.fill", tint: .cyan) {
                        EmptySettingsDestination(title: "Support")
                    }
                    SettingsNavigationRow(title: "Astrenza", icon: "app.fill", tint: .black) {
                        EmptySettingsDestination(title: "Astrenza")
                    }
                }

                Text("Astrenza 0.1.0")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 22)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.astrenzaSettingsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

private struct DisplaySettingsView: View {
    @Binding var selectedFont: String
    @Binding var selectedNameLayout: String
    @Binding var selectedActionButtons: String
    @Binding var textScale: Double
    @Binding var usesSystemTextSize: Bool

    var body: some View {
        SettingsList {
            SettingsSection(title: "POST PREVIEW") {
                SettingsPostPreviewCard()
                    .padding(16)
            }

            SettingsSection(title: "FONT") {
                SettingsChoiceRow(title: "San Francisco Rounded", selectedValue: $selectedFont)
                SettingsChoiceRow(title: "San Francisco", selectedValue: $selectedFont)
                SettingsChoiceRow(title: "Avenir", selectedValue: $selectedFont)
            }

            SettingsSection(title: "TEXT SIZE") {
                VStack(spacing: 0) {
                    SettingsToggleContent(title: "Use System Size", isOn: $usesSystemTextSize)
                    SettingsDivider()
                    HStack(spacing: 16) {
                        Text("A")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Slider(value: $textScale)
                            .tint(.secondary)
                        Text("A")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                }
            }

            SettingsSection(title: "NAME LAYOUT") {
                ForEach(["Display Name", "Account Name", "Both (Vertical)", "Both (Horizontal)"], id: \.self) { option in
                    SettingsChoiceRow(title: option, selectedValue: $selectedNameLayout)
                }
            }

            SettingsSection(title: "ACTION BUTTONS") {
                ForEach(["Large", "Small", "Drawer"], id: \.self) { option in
                    SettingsChoiceRow(title: option, selectedValue: $selectedActionButtons)
                }
            }
        }
        .settingsNavigation(title: "Display")
    }
}

private struct BehaviorsSettingsView: View {
    @Binding var isTapToTopEnabled: Bool
    @Binding var isIgnoringContentWarnings: Bool
    @Binding var isShowingSensitiveMedia: Bool
    @Binding var areEnhancedCardPreviewsEnabled: Bool
    @Binding var isContextMenuOrderFixed: Bool
    @Binding var areServerTranslationsPrioritized: Bool
    @Binding var isDragAndDropEnabled: Bool
    @Binding var areMentionsUnreadOnly: Bool

    var body: some View {
        SettingsList {
            SettingsSection {
                SettingsToggleContent(title: "Tap to Top", isOn: $isTapToTopEnabled)
            } footer: {
                "Tapping the very top of the screen scrolls the timeline to the top. Tapping again returns to the last read post."
            }

            SettingsSection(title: "SENSITIVE CONTENT") {
                SettingsToggleContent(title: "Ignore Content Warnings", isOn: $isIgnoringContentWarnings)
                SettingsDivider()
                SettingsToggleContent(title: "Show Sensitive Media", isOn: $isShowingSensitiveMedia)
            } footer: {
                "Content warnings keep posts collapsed in the timeline. Sensitive media can still be revealed per post."
            }

            SettingsSection {
                SettingsToggleContent(title: "Enhanced Card Previews", isOn: $areEnhancedCardPreviewsEnabled)
            } footer: {
                "Fetch missing link preview data from source websites when posts are loaded."
            }

            SettingsSection {
                SettingsToggleContent(title: "Fixed Context Menu Order", isOn: $isContextMenuOrderFixed)
            } footer: {
                "Keep context menu items in a fixed order instead of moving the nearest action to the active button."
            }

            SettingsSection {
                SettingsToggleContent(title: "Prioritize Server Translations", isOn: $areServerTranslationsPrioritized)
            } footer: {
                "Prefer server translation results over local Apple translation services."
            }

            SettingsSection {
                SettingsToggleContent(title: "Drag & Drop Posts", isOn: $isDragAndDropEnabled)
            } footer: {
                "Allows posts to be dragged into other apps."
            }

            SettingsSection(title: "NOTIFICATIONS") {
                SettingsToggleContent(title: "Mentions Only as Unread", isOn: $areMentionsUnreadOnly)
            }
        }
        .settingsNavigation(title: "Behaviors")
    }
}

private struct GesturesSettingsView: View {
    @Binding var longLeftSwipe: String
    @Binding var longRightSwipe: String
    @Binding var shortLeftSwipe: String
    @Binding var shortRightSwipe: String
    @Binding var isThemeSwipeEnabled: Bool

    var body: some View {
        SettingsList {
            SettingsSection(title: "LONG SWIPE") {
                GestureSettingRow(title: "Left", icon: "line.3.horizontal.decrease.circle", value: longLeftSwipe) {
                    GestureOptionSettingsView(title: "Long Left Swipe", selection: $longLeftSwipe)
                }
                GestureSettingRow(title: "Right", icon: "line.3.horizontal.decrease.circle", value: longRightSwipe) {
                    GestureOptionSettingsView(title: "Long Right Swipe", selection: $longRightSwipe)
                }
            } footer: {
                "Drag a post more than halfway across and release."
            }

            SettingsSection(title: "SHORT SWIPE") {
                GestureSettingRow(title: "Left", icon: "capsule.lefthalf.filled", value: shortLeftSwipe) {
                    GestureOptionSettingsView(title: "Short Left Swipe", selection: $shortLeftSwipe)
                }
                GestureSettingRow(title: "Right", icon: "capsule.righthalf.filled", value: shortRightSwipe) {
                    GestureOptionSettingsView(title: "Short Right Swipe", selection: $shortRightSwipe)
                }
            } footer: {
                "Drag a post less than halfway across and release."
            }

            SettingsSection {
                SettingsToggleContent(title: "Swipe to Switch Themes", isOn: $isThemeSwipeEnabled)
            } footer: {
                "Swipe up or down with two fingers to switch to the next or previous theme."
            }
        }
        .settingsNavigation(title: "Gestures")
    }
}

private struct GestureOptionSettingsView: View {
    let title: String
    @Binding var selection: String
    private let options = [
        "Favorite",
        "Repost",
        "Quote",
        "Bookmark",
        "Open Link to Post",
        "Copy Link to Post",
        "Copy Post",
        "Share Post",
        "Add to Read Later",
        "Translate",
        "Reply",
        "View Detail",
        "No Action"
    ]

    var body: some View {
        SettingsList {
            SettingsSection {
                ForEach(options, id: \.self) { option in
                    SettingsChoiceRow(title: option, selectedValue: $selection)
                }
            }
        }
        .settingsNavigation(title: title)
    }
}

private struct EmptySettingsDestination: View {
    let title: String

    var body: some View {
        SettingsList {
            SettingsSection {
                HStack(spacing: 12) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.astrenzaAccent)
                    Text("Mock screen")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(height: 60)
            }
        }
        .settingsNavigation(title: title)
    }
}

private struct NostrListSettingsView: View {
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
                            onEdit: { editorDraft = .existing(rule: rule) },
                            onDelete: { delete(rule) }
                        )
                    }
                    if !rules(for: .mutedPubkey).isEmpty {
                        SettingsDivider()
                    }
                    FilterAddButton(title: "Add User") {
                        editorDraft = .newUser(accountID: accountID ?? "")
                    }
                }
            }

            SettingsSection(title: "KEYWORDS") {
                ForEach(rules(for: .keyword), id: \.ruleID) { rule in
                    FilterOverviewRuleRow(
                        rule: rule,
                        icon: "text.quote",
                        isEditing: isEditingFilters,
                        onEdit: { editorDraft = .existing(rule: rule) },
                        onDelete: { delete(rule) }
                    )
                }
                if !rules(for: .keyword).isEmpty {
                    SettingsDivider()
                }
                FilterAddButton(title: "Add Keyword") {
                    editorDraft = .newKeyword(accountID: accountID ?? "")
                }
            }

            SettingsSection(title: "HASHTAGS") {
                ForEach(rules(for: .mutedHashtag), id: \.ruleID) { rule in
                    FilterOverviewRuleRow(
                        rule: rule,
                        icon: "number",
                        isEditing: isEditingFilters,
                        onEdit: { editorDraft = .existing(rule: rule) },
                        onDelete: { delete(rule) }
                    )
                }
                if !rules(for: .mutedHashtag).isEmpty {
                    SettingsDivider()
                }
                FilterAddButton(title: "Add Hashtag") {
                    editorDraft = .newHashtag(accountID: accountID ?? "")
                }
            }

            SettingsSection(title: "CUSTOM") {
                Button {
                    editorDraft = .potentialSpam(accountID: accountID ?? "", existing: potentialSpamRule)
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

private enum FilterEditorKind: String, Identifiable {
    case user
    case keyword
    case hashtag
    case potentialSpam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user: "Filter User"
        case .keyword: "Filter Keyword"
        case .hashtag: "Filter Hashtag"
        case .potentialSpam: "Filter Potential Spam"
        }
    }
}

private enum FilterApplicationScope: String, CaseIterable, Identifiable {
    case home = "Home"
    case mentions = "Mentions & Notifications"
    case threads = "Threads"
    case lists = "Lists"
    case publicTimelines = "Public Timelines"

    var id: String { rawValue }
}

private struct FilterCandidateUser: Identifiable {
    let id: String
    let displayName: String
    let npub: String
    let nip05: String
    let avatar: AvatarStyle

    static let mockCandidates: [FilterCandidateUser] = [
        FilterCandidateUser(
            id: String(repeating: "1", count: 64),
            displayName: "User Alpha",
            npub: "npub1alpha7q3n9...9h2q",
            nip05: "alpha@mock.example",
            avatar: AvatarStyle(primary: .cyan, secondary: .indigo, symbolName: "sparkles")
        ),
        FilterCandidateUser(
            id: String(repeating: "2", count: 64),
            displayName: "Relay Maintainer",
            npub: "npub1relay4j5m...2x8v",
            nip05: "relay@mock.example",
            avatar: AvatarStyle(primary: .green, secondary: .mint, symbolName: "antenna.radiowaves.left.and.right")
        ),
        FilterCandidateUser(
            id: String(repeating: "3", count: 64),
            displayName: "Media Curator",
            npub: "npub1media6z8k...7n4c",
            nip05: "media@mock.example",
            avatar: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "photo.fill")
        )
    ]
}

private struct FilterEditorDraft: Identifiable {
    static let potentialSpamRuleIDPrefix = "local:custom:potential-spam:"
    private static let potentialSpamPattern = "(?i)\\b(airdrop|giveaway|free\\s+crypto|limited\\s+offer)\\b"

    let id = UUID()
    let kind: FilterEditorKind
    var value: String
    var isEnabled: Bool
    var masksWithWarning: Bool
    var selectedScopes: Set<FilterApplicationScope>
    var selectedUser: FilterCandidateUser?
    var matchingCount: Int
    var totalCount: Int

    static func newKeyword(accountID: String) -> FilterEditorDraft {
        FilterEditorDraft(
            kind: .keyword,
            value: "",
            isEnabled: true,
            masksWithWarning: false,
            selectedScopes: [.home, .lists, .publicTimelines],
            selectedUser: nil,
            matchingCount: 0,
            totalCount: 3_944
        )
    }

    static func newHashtag(accountID: String) -> FilterEditorDraft {
        FilterEditorDraft(
            kind: .hashtag,
            value: "",
            isEnabled: true,
            masksWithWarning: false,
            selectedScopes: [.home, .lists, .publicTimelines],
            selectedUser: nil,
            matchingCount: 0,
            totalCount: 3_944
        )
    }

    static func newUser(accountID: String) -> FilterEditorDraft {
        FilterEditorDraft(
            kind: .user,
            value: "",
            isEnabled: true,
            masksWithWarning: false,
            selectedScopes: [.home],
            selectedUser: nil,
            matchingCount: 0,
            totalCount: 3_944
        )
    }

    static func potentialSpam(accountID: String, existing: NostrFilterRuleRecord?) -> FilterEditorDraft {
        FilterEditorDraft(
            kind: .potentialSpam,
            value: potentialSpamPattern,
            isEnabled: existing?.isEnabled ?? false,
            masksWithWarning: true,
            selectedScopes: [.home],
            selectedUser: nil,
            matchingCount: 0,
            totalCount: 4_001
        )
    }

    static func existing(rule: NostrFilterRuleRecord) -> FilterEditorDraft {
        switch rule.kind {
        case .mutedPubkey:
            let candidate = FilterCandidateUser(
                id: rule.value,
                displayName: "Muted User",
                npub: rule.value.abbreviatedMiddle,
                nip05: "unresolved@mock.example",
                avatar: AvatarStyle(primary: .gray, secondary: .purple, symbolName: "person.crop.circle.fill")
            )
            return FilterEditorDraft(
                kind: .user,
                value: rule.value,
                isEnabled: rule.isEnabled,
                masksWithWarning: false,
                selectedScopes: [.home],
                selectedUser: candidate,
                matchingCount: 2,
                totalCount: 3_944
            )
        case .keyword:
            return FilterEditorDraft(
                kind: .keyword,
                value: rule.value,
                isEnabled: rule.isEnabled,
                masksWithWarning: false,
                selectedScopes: [.home, .lists, .publicTimelines],
                selectedUser: nil,
                matchingCount: 0,
                totalCount: 3_944
            )
        case .mutedHashtag:
            return FilterEditorDraft(
                kind: .hashtag,
                value: rule.value,
                isEnabled: rule.isEnabled,
                masksWithWarning: false,
                selectedScopes: [.home, .lists, .publicTimelines],
                selectedUser: nil,
                matchingCount: 0,
                totalCount: 3_944
            )
        default:
            return potentialSpam(accountID: rule.accountID, existing: rule)
        }
    }

    var canSave: Bool {
        switch kind {
        case .user:
            selectedUser != nil
        case .keyword, .hashtag:
            !normalizedValue.isEmpty
        case .potentialSpam:
            true
        }
    }

    var normalizedValue: String {
        switch kind {
        case .hashtag:
            value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("#").lowercased()
        case .keyword:
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .user:
            selectedUser?.id ?? value
        case .potentialSpam:
            Self.potentialSpamPattern
        }
    }

    func rule(accountID: String, now: Int) -> NostrFilterRuleRecord {
        let ruleKind: NostrFilterRuleKind
        let ruleID: String
        let ruleValue: String

        switch kind {
        case .user:
            ruleKind = .mutedPubkey
            ruleValue = normalizedValue
            ruleID = "local:filter-user:\(accountID):\(ruleValue)"
        case .keyword:
            ruleKind = .keyword
            ruleValue = normalizedValue
            ruleID = "local:filter-keyword:\(accountID):\(ruleValue.lowercased())"
        case .hashtag:
            ruleKind = .mutedHashtag
            ruleValue = normalizedValue
            ruleID = "local:filter-hashtag:\(accountID):\(ruleValue)"
        case .potentialSpam:
            ruleKind = .regex
            ruleValue = normalizedValue
            ruleID = "\(Self.potentialSpamRuleIDPrefix)\(accountID)"
        }

        return NostrFilterRuleRecord(
            ruleID: ruleID,
            accountID: accountID,
            kind: ruleKind,
            value: ruleValue,
            isEnabled: isEnabled,
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct NostrLocalStateRow: View {
    let icon: String
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: icon, tint: tint)
            Text(title)
                .font(.system(size: 17, weight: .black, design: .rounded))
            Spacer()
            Text("\(value)")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }
}

private struct FilterAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color.astrenzaAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FilterOverviewRuleRow: View {
    let rule: NostrFilterRuleRecord
    let icon: String
    let isEditing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    SettingsIcon(systemName: icon, tint: rule.isEnabled ? .orange : .gray)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayValue)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(rule.kind.displayTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(rule.isEnabled ? "Enabled" : "Disabled")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(rule.isEnabled ? Color.astrenzaAccent : .secondary)
                }
            }
            .buttonStyle(.plain)

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 58)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private var displayValue: String {
        switch rule.kind {
        case .mutedPubkey:
            rule.value.abbreviatedMiddle
        case .mutedHashtag:
            "#\(rule.value)"
        default:
            rule.value
        }
    }
}

private struct FilterEditorSheet: View {
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

private struct FilterCandidateUserRow: View {
    let candidate: FilterCandidateUser

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(style: candidate.avatar, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(candidate.displayName)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(candidate.nip05)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(candidate.npub)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 74)
        .contentShape(Rectangle())
    }
}

private struct FilterSelectedUserRow: View {
    let candidate: FilterCandidateUser

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(style: candidate.avatar, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayName)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                Text(candidate.nip05)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(candidate.npub)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct FilterToggleLine: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Color.astrenzaAccent)
        .padding(.horizontal, 18)
        .frame(minHeight: subtitle == nil ? 66 : 86)
        .settingsRowTextStyle()
    }
}

private struct FilterScopeToggleRow: View {
    let scope: FilterApplicationScope
    @Binding var isOn: Bool

    var body: some View {
        Toggle(scope.rawValue, isOn: $isOn)
            .toggleStyle(.switch)
            .tint(Color.astrenzaAccent)
            .padding(.horizontal, 18)
            .frame(height: 64)
            .settingsRowTextStyle()
    }
}

private struct NostrListSummaryRow: View {
    let summary: NostrListSummary
    let items: [NostrListItemRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SettingsIcon(systemName: iconName, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(displayTitle)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .lineLimit(1)
                        Text("kind:\(summary.kind)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(summary.visibility)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(items.prefix(5), id: \.rowID) { item in
                        NostrListItemLine(item: item)
                    }
                    if items.count > 5 {
                        Text("+\(items.count - 5) more")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 46)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var displayTitle: String {
        summary.title ?? kindTitle
    }

    private var kindTitle: String {
        switch summary.kind {
        case 10_000: "Mute List"
        case 10_003: "Bookmarks"
        case 10_007: "Search Relays"
        case 30_000: "Follow Set"
        case 30_002: "Relay Set"
        case 30_003: "Bookmark Set"
        default: "List"
        }
    }

    private var iconName: String {
        switch summary.kind {
        case 10_000: "speaker.slash.fill"
        case 10_003, 30_003: "bookmark.fill"
        case 10_007, 30_002: "antenna.radiowaves.left.and.right"
        case 30_000: "person.2.fill"
        default: "list.bullet"
        }
    }

    private var tint: Color {
        switch summary.kind {
        case 10_000: .orange
        case 10_003, 30_003: .purple
        case 10_007, 30_002: .green
        case 30_000: .cyan
        default: .gray
        }
    }
}

private struct NostrListItemLine: View {
    let item: NostrListItemRecord

    var body: some View {
        HStack(spacing: 7) {
            Text(item.itemType)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Color.astrenzaAccent)
                .frame(width: 52, alignment: .leading)
            Text(displayValue)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private var displayValue: String {
        switch item.itemType {
        case "pubkey", "event", "address":
            item.value.abbreviatedMiddle
        default:
            item.value
        }
    }
}

private struct NostrListEmptyRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIcon(systemName: icon, tint: .gray)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct AccountSettingsView: View {
    let title: String
    let subtitle: String
    let avatarStyle: AvatarStyle
    let accountID: String?
    let eventStore: NostrEventStore?

    private var abbreviatedNpub: String {
        title.contains("Beta") ? "npub1beta4x2ck8...w6mx" : "npub1astrenza7q3n9...9h2q"
    }

    var body: some View {
        SettingsList {
            SettingsSection {
                HStack(spacing: 14) {
                    AvatarView(style: avatarStyle, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                        Text(subtitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(abbreviatedNpub)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            SettingsSection(title: "NOSTR ACCOUNT") {
                SettingsNavigationRow(title: "Profile", icon: "person.crop.circle.fill", tint: .cyan) {
                    EmptySettingsDestination(title: "Profile")
                }
                SettingsValueNavigationRow(title: "Keys / Signer", value: "Local", icon: "key.fill", tint: .purple) {
                    EmptySettingsDestination(title: "Keys / Signer")
                }
                SettingsStatusNavigationRow(title: "Relays", statusColor: .green, icon: "antenna.radiowaves.left.and.right", tint: .green) {
                    RelaySettingsView(accountID: accountID, eventStore: eventStore)
                }
                SettingsNavigationRow(title: "Muting / Filters", icon: "line.3.horizontal.decrease.circle.fill", tint: .orange) {
                    NostrListSettingsView(accountID: accountID, eventStore: eventStore)
                }
                SettingsNavigationRow(title: "Backup / Export", icon: "square.and.arrow.up.fill", tint: .gray) {
                    EmptySettingsDestination(title: "Backup / Export")
                }
            } footer: {
                "These settings belong to this Nostr identity. Switching accounts should switch relay lists, signer permissions, filters, and backup state."
            }
        }
        .settingsNavigation(title: title)
    }
}

private struct SettingsList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content()
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .padding(.bottom, 40)
        }
        .background(Color.astrenzaSettingsBackground.ignoresSafeArea())
    }
}

private struct SettingsSection<Content: View>: View {
    var title: String?
    @ViewBuilder let content: () -> Content
    var footer: (() -> String)?

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content, footer: (() -> String)? = nil) {
        self.title = title
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .settingsSectionTitleStyle()
                    .padding(.horizontal, 14)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(Color.astrenzaSettingsCard, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            if let footerText = footer?() {
                Text(footerText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
            }
        }
    }
}

private struct SettingsNavigationRow<Destination: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowShell(icon: icon, tint: tint) {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .settingsChevronStyle()
            }
        }
        .buttonStyle(.plain)
        .settingsRowTextStyle()
    }
}

private struct SettingsValueNavigationRow<Destination: View>: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowShell(icon: icon, tint: tint) {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .settingsChevronStyle()
            }
        }
        .buttonStyle(.plain)
        .settingsRowTextStyle()
    }
}

private struct SettingsStatusNavigationRow<Destination: View>: View {
    let title: String
    let statusColor: Color
    let icon: String
    let tint: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowShell(icon: icon, tint: tint) {
                Text(title)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Image(systemName: "chevron.right")
                    .settingsChevronStyle()
            }
        }
        .buttonStyle(.plain)
        .settingsRowTextStyle()
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let icon: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        SettingsRowShell(icon: icon, tint: tint) {
            SettingsToggleContent(title: title, isOn: $isOn)
                .padding(.leading, -18)
        }
        .settingsRowTextStyle()
    }
}

private struct SettingsAccountRow: View {
    let title: String
    let subtitle: String
    let avatarStyle: AvatarStyle
    let accountID: String?
    let eventStore: NostrEventStore?

    var body: some View {
        NavigationLink {
            AccountSettingsView(
                title: title,
                subtitle: subtitle,
                avatarStyle: avatarStyle,
                accountID: accountID,
                eventStore: eventStore
            )
        } label: {
            SettingsRowShell(iconView: {
                AvatarView(style: avatarStyle, size: 36)
            }) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .settingsChevronStyle()
            }
        }
        .buttonStyle(.plain)
        .settingsRowTextStyle()
    }
}

private struct SettingsRowShell<Icon: View, Content: View>: View {
    @ViewBuilder let iconView: () -> Icon
    @ViewBuilder let content: () -> Content

    init(icon: String, tint: Color, @ViewBuilder content: @escaping () -> Content) where Icon == SettingsIcon {
        self.iconView = {
            SettingsIcon(systemName: icon, tint: tint)
        }
        self.content = content
    }

    init(@ViewBuilder iconView: @escaping () -> Icon, @ViewBuilder content: @escaping () -> Content) {
        self.iconView = iconView
        self.content = content
    }

    var body: some View {
        HStack(spacing: 14) {
            iconView()
                .frame(width: 42)
            content()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            SettingsDivider()
                .padding(.leading, 72)
        }
    }
}

private struct SettingsToggleContent: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
        }
        .toggleStyle(.switch)
        .tint(.blue)
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
        .settingsRowTextStyle()
    }
}

private struct SettingsChoiceRow: View {
    let title: String
    @Binding var selectedValue: String

    var body: some View {
        Button {
            selectedValue = title
        } label: {
            HStack {
                Text(title)
                Spacer()
                if selectedValue == title {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsRowTextStyle()
        .overlay(alignment: .bottom) {
            SettingsDivider()
                .padding(.leading, 18)
        }
    }
}

private struct GestureSettingRow<Destination: View>: View {
    let title: String
    let icon: String
    let value: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowShell(icon: icon, tint: .blue) {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .settingsChevronStyle()
            }
        }
        .buttonStyle(.plain)
        .settingsRowTextStyle()
    }
}

private struct SettingsIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.gradient)
            Image(systemName: systemName)
                .font(.system(size: 21, weight: .black))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }
}

private struct SettingsPostPreviewCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(style: AvatarStyle(primary: .black, secondary: .red, symbolName: "app.fill"), size: 48)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Astrenza")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                        Text("alpha@mock.example")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("1m")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text("Thanks for trying Astrenza. Tune the timeline until it feels exactly right.")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 30) {
                    Image(systemName: "bubble.left")
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Image(systemName: "star.fill")
                    Image(systemName: "square.and.arrow.up")
                    Image(systemName: "gearshape")
                }
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.primary)
        .padding(14)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.astrenzaSeparator)
            .frame(height: 1)
    }
}

private extension NostrListItemRecord {
    var rowID: String {
        "\(listID):\(position):\(itemKey)"
    }
}

private extension String {
    var abbreviatedMiddle: String {
        guard count > 18 else { return self }
        return "\(prefix(10))...\(suffix(8))"
    }

    func trimmingPrefix(_ prefix: Character) -> String {
        var trimmed = self
        while trimmed.first == prefix {
            trimmed.removeFirst()
        }
        return trimmed
    }
}

private extension NostrFilterRuleKind {
    var displayTitle: String {
        switch self {
        case .mutedPubkey: "User"
        case .mutedHashtag: "Hashtag"
        case .keyword: "Keyword"
        case .regex: "Custom"
        case .mutedKind: "Kind"
        case .relayMute: "Relay"
        }
    }
}

private extension View {
    func settingsNavigation(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.astrenzaSettingsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    func settingsRowTextStyle() -> some View {
        font(.system(size: 19, weight: .regular, design: .rounded))
            .foregroundStyle(.primary)
    }

    func settingsChevronStyle() -> some View {
        font(.system(size: 17, weight: .bold))
            .foregroundStyle(.tertiary)
    }

    func settingsSectionTitleStyle() -> some View {
        font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

private extension Color {
    static let astrenzaSettingsBackground = Color(red: 0.095, green: 0.095, blue: 0.105)
    static let astrenzaSettingsCard = Color(red: 0.17, green: 0.17, blue: 0.18)
}
