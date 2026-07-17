import AstrenzaCore
import SwiftUI

struct RelaySettingsView: View {
    let accountID: String?
    let eventStore: NostrEventStore?
    let onSyncPolicyChange: (NostrSyncPolicy) -> Void
    @State private var selectedSection: RelaySettingsSection = .nip65
    @State private var draftRelayURL = "wss://"
    @State private var isPublishingNIP65 = true
    @State private var syncPolicy: NostrSyncPolicy
    @State private var mediaResolverSettings: NostrMediaResolverServiceSettings
    private let syncPolicyStore: NostrSyncPolicySettingsStore
    private let mediaResolverSettingsStore: NostrMediaResolverSettingsStore
    private let liveNIP65Relays: [RelayDescriptor]?

    init(
        accountID: String? = nil,
        eventStore: NostrEventStore? = nil,
        syncPolicyStore: NostrSyncPolicySettingsStore = .shared,
        mediaResolverSettingsStore: NostrMediaResolverSettingsStore = .shared,
        onSyncPolicyChange: @escaping (NostrSyncPolicy) -> Void = { _ in }
    ) {
        self.accountID = accountID
        self.eventStore = eventStore
        self.syncPolicyStore = syncPolicyStore
        self.mediaResolverSettingsStore = mediaResolverSettingsStore
        self.onSyncPolicyChange = onSyncPolicyChange
        if let accountID {
            let relayListEvent = try? eventStore?.latestReplaceableEvent(
                pubkey: accountID,
                kind: 10_002
            )
            let preferences = (try? eventStore?.relayPreferences(
                accountID: accountID
            )) ?? []
            liveNIP65Relays = RelaySettingsLiveProjection.nip65Relays(
                event: relayListEvent ?? nil,
                preferences: preferences
            )
        } else {
            liveNIP65Relays = nil
        }
        _syncPolicy = State(initialValue: syncPolicyStore.policy(accountID: accountID))
        _mediaResolverSettings = State(initialValue: mediaResolverSettingsStore.settings())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                RelaySettingsHeader(isPublishingNIP65: $isPublishingNIP65)

                RelaySyncPolicyCard(policy: $syncPolicy)

                RelayMediaResolverServiceCard(settings: $mediaResolverSettings)

                Picker("Relay Section", selection: $selectedSection) {
                    ForEach(RelaySettingsSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                sectionContent

                RelayAddCard(draftRelayURL: $draftRelayURL)
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .background(Color.astrenzaBackground.ignoresSafeArea())
        .navigationTitle("Relays")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: syncPolicy) { _, policy in
            syncPolicyStore.save(policy, accountID: accountID)
            onSyncPolicyChange(policy)
        }
        .onChange(of: mediaResolverSettings) { _, settings in
            mediaResolverSettingsStore.save(settings)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Publish") {}
                    .fontWeight(.bold)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .nip65:
            RelaySettingsListCard(
                title: "NIP-65 Home Relays",
                subtitle: "Read/write relays published as kind:10002.",
                relays: liveNIP65Relays ?? RelayMockStore.relays.filter {
                    $0.source == .nip65 || $0.source == .manual
                },
                showsUsageControls: true,
                accountID: accountID,
                eventStore: eventStore
            )
        case .dm:
            RelaySettingsListCard(
                title: "DM Inbox Relays",
                subtitle: "Used for gift wraps and private message discovery.",
                relays: liveNIP65Relays == nil ? RelayMockStore.relays.filter {
                    $0.usage.contains(.dm) || $0.source == .nip17
                } : [],
                showsUsageControls: false,
                accountID: accountID,
                eventStore: eventStore
            )
        case .discovery:
            RelaySettingsListCard(
                title: "Search / Discovery",
                subtitle: "Indexers, search relays, and recommended bootstrap relays.",
                relays: liveNIP65Relays == nil ?
                    RelayMockStore.relays.filter { $0.usage.contains(.search) } +
                    RelayMockStore.recommended : [],
                showsUsageControls: false,
                accountID: accountID,
                eventStore: eventStore
            )
        case .blocked:
            RelaySettingsListCard(
                title: "Blocked / Trusted",
                subtitle: "Local relay policy and trust decisions.",
                relays: liveNIP65Relays == nil ? RelayMockStore.relays.filter {
                    $0.source == .blocked
                } : [],
                showsUsageControls: false,
                accountID: accountID,
                eventStore: eventStore
            )
        }
    }
}

enum RelaySettingsLiveProjection {
    static func nip65Relays(
        event: NostrEvent?,
        preferences: [NostrRelayPreferenceRecord]
    ) -> [RelayDescriptor] {
        let preferencesByURL = Dictionary(
            preferences.map { ($0.relayURL, $0) },
            uniquingKeysWith: { current, latest in
                current.updatedAt >= latest.updatedAt ? current : latest
            }
        )
        return NostrRelayList.parse(from: event).items.map { item in
            let preference = preferencesByURL[item.url]
            return RelayDescriptor.liveConfiguration(
                url: item.url,
                isEnabled: preference?.isEnabled ?? true,
                canRead: preference?.readEnabled ?? item.canRead,
                canWrite: preference?.writeEnabled ?? item.canWrite
            )
        }
    }
}

private enum RelaySettingsSection: String, CaseIterable, Identifiable {
    case nip65
    case dm
    case discovery
    case blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nip65: "NIP-65"
        case .dm: "DM"
        case .discovery: "Discover"
        case .blocked: "Policy"
        }
    }
}

private struct RelaySettingsHeader: View {
    @Binding var isPublishingNIP65: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Relay Configuration")
                        .font(.system(size: 25, weight: .black, design: .rounded))
                    Text("Separate the relays you read from, publish to, discover through, and keep private.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(Color.astrenzaAccent)
                    .frame(width: 50, height: 50)
                    .background(Color.astrenzaAccent.opacity(0.16), in: Circle())
            }

            Toggle(isOn: $isPublishingNIP65) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Publish NIP-65 relay list")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    Text("Mock: this would sign and broadcast kind:10002.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.astrenzaAccent)
        }
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct RelaySyncPolicyCard: View {
    @Binding var policy: NostrSyncPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(Color.astrenzaAccent)
                    .frame(width: 48, height: 48)
                    .background(Color.astrenzaAccent.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Sync & Traffic")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                    Text("Choose how aggressively Home TL asks relays for followed authors, media, and OGP.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Sync Mode")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                Picker("Sync Mode", selection: $policy.mode) {
                    ForEach(NostrSyncMode.allCases, id: \.rawValue) { mode in
                        Text(mode.settingsTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Network Assumption")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                Picker("Network", selection: $policy.networkType) {
                    ForEach(NostrNetworkType.allCases, id: \.rawValue) { networkType in
                        Text(networkType.settingsTitle).tag(networkType)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(spacing: 0) {
                RelayPolicyToggle(
                    title: "Tap to Load Media",
                    subtitle: "Do not fetch remote images and videos until the row is tapped.",
                    isOn: $policy.tapToLoadMedia
                )
                Divider().overlay(Color.white.opacity(0.08))
                RelayPolicyToggle(
                    title: "Queue OGP Previews",
                    subtitle: "Resolve link cards in the background instead of blocking timeline rendering.",
                    isOn: $policy.queueOGPPreviews
                )
                Divider().overlay(Color.white.opacity(0.08))
                RelayPolicyToggle(
                    title: "Disable OGP on Cellular",
                    subtitle: "Keep links clickable but skip preview fetching while on cellular.",
                    isOn: $policy.disableOGPOnCellular
                )
            }
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct RelayMediaResolverServiceCard: View {
    @Binding var settings: NostrMediaResolverServiceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(Color.astrenzaAccent)
                    .frame(width: 48, height: 48)
                    .background(Color.astrenzaAccent.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Media Resolver Service")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                    Text(settings.configuration.isUsable ? "Ready" : "Disabled or incomplete")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $settings.isEnabled) {
                Text("Use service for OGP")
                    .font(.system(size: 15, weight: .black, design: .rounded))
            }
            .tint(Color.astrenzaAccent)

            VStack(alignment: .leading, spacing: 8) {
                Text("Service URL")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("https://media.example.com", text: $settings.serviceURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(12)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Bearer Token")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                SecureField("Token", text: $settings.bearerToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(12)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct RelayPolicyToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.astrenzaAccent)
        .padding(14)
    }
}

private struct RelaySettingsListCard: View {
    let title: String
    let subtitle: String
    let relays: [RelayDescriptor]
    let showsUsageControls: Bool
    let accountID: String?
    let eventStore: NostrEventStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(relays) { relay in
                    RelayEditableRow(
                        relay: relay,
                        showsUsageControls: showsUsageControls,
                        accountID: accountID,
                        eventStore: eventStore
                    )
                    if relay.id != relays.last?.id {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct RelayEditableRow: View {
    let relay: RelayDescriptor
    let showsUsageControls: Bool
    let accountID: String?
    let eventStore: NostrEventStore?
    @State private var isReadEnabled: Bool
    @State private var isWriteEnabled: Bool
    @State private var isEnabled: Bool

    init(
        relay: RelayDescriptor,
        showsUsageControls: Bool,
        accountID: String?,
        eventStore: NostrEventStore?
    ) {
        self.relay = relay
        self.showsUsageControls = showsUsageControls
        self.accountID = accountID
        self.eventStore = eventStore
        _isReadEnabled = State(initialValue: relay.usage.contains(.read))
        _isWriteEnabled = State(initialValue: relay.usage.contains(.write))
        _isEnabled = State(initialValue: relay.status != .offline)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: relay.status.icon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(relay.status.tint)
                    .frame(width: 38, height: 38)
                    .background(relay.status.tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(relay.host)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .lineLimit(1)
                    Text("\(relay.source.rawValue) / \(relay.status.rawValue)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .tint(Color.astrenzaAccent)
            }

            if showsUsageControls {
                HStack(spacing: 8) {
                    RelayUsageToggle(title: "Read", icon: "arrow.down", isOn: $isReadEnabled)
                    RelayUsageToggle(title: "Write", icon: "arrow.up", isOn: $isWriteEnabled)
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(relay.usage) { usage in
                        Label(usage.rawValue, systemImage: usage.icon)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .onChange(of: isEnabled) { _, _ in savePreference() }
        .onChange(of: isReadEnabled) { _, _ in savePreference() }
        .onChange(of: isWriteEnabled) { _, _ in savePreference() }
    }

    private func savePreference() {
        guard let accountID, let eventStore else { return }
        try? eventStore.saveRelayPreference(NostrRelayPreferenceRecord(
            accountID: accountID,
            relayURL: relay.url,
            isEnabled: isEnabled,
            readEnabled: isReadEnabled,
            writeEnabled: isWriteEnabled,
            updatedAt: Int(Date().timeIntervalSince1970)
        ))
    }
}

private struct RelayUsageToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isOn ? .black : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isOn ? Color.astrenzaAccent : Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct RelayAddCard: View {
    @Binding var draftRelayURL: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Relay")
                .font(.system(size: 20, weight: .black, design: .rounded))
            HStack(spacing: 10) {
                TextField("wss://relay.example", text: $draftRelayURL)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 13)
                    .frame(height: 46)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))

                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .black))
                        .frame(width: 46, height: 46)
                        .background(Color.astrenzaAccent, in: Circle())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            Text("Real flow should validate URL, fetch NIP-11, then mark read/write before publishing NIP-65.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
    }
}

private extension NostrSyncMode {
    var settingsTitle: String {
        switch self {
        case .ownRelayList:
            "3 / 10002"
        case .fullOutbox:
            "Full Outbox"
        }
    }
}

private extension NostrNetworkType {
    var settingsTitle: String {
        switch self {
        case .wifi:
            "Wi-Fi"
        case .cellular:
            "Cellular"
        case .other:
            "Other"
        case .unknown:
            "Auto"
        }
    }
}

#Preview {
    NavigationStack {
        RelaySettingsView()
    }
}
