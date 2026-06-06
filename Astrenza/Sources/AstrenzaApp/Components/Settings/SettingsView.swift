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
    @State private var localFilterCount = 0
    @State private var localBookmarkCount = 0
    @State private var loadError: String?

    var body: some View {
        SettingsList {
            SettingsSection(title: "LOCAL STATE") {
                if accountID == nil || eventStore == nil {
                    NostrListEmptyRow(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "No live account",
                        subtitle: "Local mute rules and bookmarks are account scoped."
                    )
                } else {
                    NostrLocalStateRow(
                        icon: "line.3.horizontal.decrease.circle.fill",
                        title: "Local Filters",
                        value: localFilterCount,
                        tint: .orange
                    )
                    SettingsDivider()
                    NostrLocalStateRow(
                        icon: "bookmark.fill",
                        title: "Local Bookmarks",
                        value: localBookmarkCount,
                        tint: .purple
                    )
                }
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
        .settingsNavigation(title: "Muting / Filters")
        .onAppear(perform: reload)
    }

    private func reload() {
        guard let accountID, let eventStore else {
            summaries = []
            itemsByListID = [:]
            localFilterCount = 0
            localBookmarkCount = 0
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
            localFilterCount = try eventStore.filterRules(accountID: accountID).count
            localBookmarkCount = try eventStore.localBookmarks(accountID: accountID).count
            loadError = nil
        } catch {
            summaries = []
            itemsByListID = [:]
            localFilterCount = 0
            localBookmarkCount = 0
            loadError = error.localizedDescription
        }
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
