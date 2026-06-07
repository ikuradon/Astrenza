import AstrenzaCore
import SwiftUI

struct RelayStatusSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: RelayStatusSheetStore
    @State private var selectedRelayURL: String?
    private let relayURLs: [String]
    private var relayRuntimeStates: [String: NostrRelayConnectionState]

    init(
        relayURLs: [String] = [],
        relayRuntimeStates: [String: NostrRelayConnectionState] = [:],
        accountID: String? = nil,
        eventStore: NostrEventStore? = nil
    ) {
        _store = StateObject(wrappedValue: RelayStatusSheetStore(
            relayURLs: relayURLs,
            relayRuntimeStates: relayRuntimeStates,
            accountID: accountID,
            eventStore: eventStore
        ))
        self.relayURLs = relayURLs
        self.relayRuntimeStates = relayRuntimeStates
        _selectedRelayURL = State(initialValue: relayURLs.first ?? (accountID == nil ? RelayMockStore.relays.first?.url : nil))
    }

    private var selectedRelay: RelayDescriptor? {
        store.relays.first { $0.url == selectedRelayURL } ?? store.relays.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RelayStatusSummaryCard(
                        connected: store.connectedCount,
                        planned: store.plannedCount,
                        relays: store.relays
                    )

                    OutboxStatusCard(summary: store.outboxSummary)

                    RelayConnectionLogCard(
                        activities: store.recentActivity,
                        relays: store.relays,
                        isLive: store.isLive
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("RELAYS")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)

                        ForEach(store.relays) { relay in
                            Button {
                                withAnimation(.snappy(duration: 0.22)) {
                                    selectedRelayURL = relay.url
                                }
                            } label: {
                                RelayStatusRow(relay: relay, isSelected: relay.url == selectedRelay?.url)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let selectedRelay {
                        RelayInfoPanel(relay: selectedRelay)
                    }
                }
                .padding(18)
                .padding(.bottom, 22)
            }
            .background(Color.astrenzaBackground.ignoresSafeArea())
            .navigationTitle("Relay Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await store.refresh()
        }
        .onChange(of: relayRuntimeStates) { _, states in
            store.updateRuntimeStates(states)
        }
        .onChange(of: relayURLs) { _, urls in
            store.updateRelayURLs(urls)
            if selectedRelayURL == nil || !store.relays.contains(where: { $0.url == selectedRelayURL }) {
                selectedRelayURL = store.relays.first?.url
            }
        }
    }
}

@MainActor
final class RelayStatusSheetStore: ObservableObject {
    @Published private(set) var relays: [RelayDescriptor]
    @Published fileprivate var outboxSummary: OutboxStatusSummary
    @Published fileprivate var recentActivity: [RelayActivityItem]

    let isLive: Bool
    private let client: any NostrRelayInformationFetching
    private let accountID: String?
    private let eventStore: NostrEventStore?
    private var relayRuntimeStates: [String: NostrRelayConnectionState]

    init(
        relayURLs: [String],
        relayRuntimeStates: [String: NostrRelayConnectionState] = [:],
        accountID: String?,
        eventStore: NostrEventStore?,
        client: any NostrRelayInformationFetching = NostrRelayInformationClient()
    ) {
        isLive = accountID != nil || !relayURLs.isEmpty
        self.client = client
        self.accountID = accountID
        self.eventStore = eventStore
        self.relayRuntimeStates = relayRuntimeStates
        let initialRelays = Self.initialRelays(
            relayURLs: relayURLs,
            isLive: isLive,
            relayRuntimeStates: relayRuntimeStates,
            accountID: accountID,
            eventStore: eventStore
        )
        relays = initialRelays
        outboxSummary = Self.loadOutboxSummary(accountID: accountID, eventStore: eventStore)
        recentActivity = Self.loadRecentActivity(accountID: accountID, eventStore: eventStore, relays: initialRelays)
    }

    func updateRelayURLs(_ relayURLs: [String]) {
        guard isLive else { return }
        relays = Self.initialRelays(
            relayURLs: relayURLs,
            isLive: isLive,
            relayRuntimeStates: relayRuntimeStates,
            accountID: accountID,
            eventStore: eventStore
        )
        recentActivity = Self.loadRecentActivity(accountID: accountID, eventStore: eventStore, relays: relays)
    }

    func updateRuntimeStates(_ states: [String: NostrRelayConnectionState]) {
        relayRuntimeStates = states
        relays = relays.map { relay in
            relay.withRuntimeState(states[relay.url])
        }
    }

    var connectedCount: Int {
        relays.filter { $0.status == .online || $0.status == .authRequired || $0.status == .paymentRequired }.count
    }

    var plannedCount: Int {
        relays.count
    }

    func refresh() async {
        guard isLive else { return }
        outboxSummary = Self.loadOutboxSummary(accountID: accountID, eventStore: eventStore)
        recentActivity = Self.loadRecentActivity(accountID: accountID, eventStore: eventStore, relays: relays)
        for relay in relays {
            let startedAt = Int(Date().timeIntervalSince1970)
            let descriptor: RelayDescriptor
            do {
                let info = try await client.information(for: relay.url)
                descriptor = RelayDescriptor.live(url: relay.url, information: info)
                try? eventStore?.saveRelayProfile(NostrRelayProfileRecord(
                    relayURL: relay.url,
                    information: info,
                    healthScore: 1,
                    lastEOSEAt: nil,
                    lastConnectedAt: startedAt,
                    authRequired: info.limitation?.authRequired == true,
                    paymentRequired: info.limitation?.paymentRequired == true
                ))
            } catch {
                descriptor = RelayDescriptor.liveFailure(url: relay.url, error: error)
            }

            guard let index = relays.firstIndex(where: { $0.url == relay.url }) else { continue }
            let summary = Self.loadSummaries(accountID: accountID, eventStore: eventStore)[relay.url]
            let cursor = Self.loadCursor(accountID: accountID, eventStore: eventStore, relayURL: relay.url)
            let appliedDescriptor = descriptor.applying(summary: summary, cursor: cursor)
            relays[index] = summary == nil
                ? appliedDescriptor.preservingConnectionState(from: relay).withRuntimeState(relayRuntimeStates[relay.url])
                : appliedDescriptor.withRuntimeState(relayRuntimeStates[relay.url])
            recentActivity = Self.loadRecentActivity(accountID: accountID, eventStore: eventStore, relays: relays)
        }
    }

    private static func initialRelays(
        relayURLs: [String],
        isLive: Bool,
        relayRuntimeStates: [String: NostrRelayConnectionState],
        accountID: String?,
        eventStore: NostrEventStore?
    ) -> [RelayDescriptor] {
        guard !relayURLs.isEmpty else {
            return isLive ? [] : RelayMockStore.relays
        }
        let summaries = loadSummaries(accountID: accountID, eventStore: eventStore)
        let cursors = loadCursors(accountID: accountID, eventStore: eventStore, relayURLs: relayURLs)
        return relayURLs.map { relayURL in
            RelayDescriptor.livePlaceholder(url: relayURL)
                .applying(summary: summaries[relayURL], cursor: cursors[relayURL])
                .withRuntimeState(relayRuntimeStates[relayURL])
        }
    }

    private static func loadSummaries(
        accountID: String?,
        eventStore: NostrEventStore?
    ) -> [String: NostrRelaySyncSummaryRecord] {
        guard let accountID,
              let summaries = try? eventStore?.relaySyncSummaries(accountID: accountID, timelineKey: "home")
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: summaries.map { ($0.relayURL, $0) })
    }

    private static func loadCursors(
        accountID: String?,
        eventStore: NostrEventStore?,
        relayURLs: [String]
    ) -> [String: NostrSyncCursorRecord] {
        Dictionary(uniqueKeysWithValues: relayURLs.compactMap { relayURL in
            guard let cursor = loadCursor(accountID: accountID, eventStore: eventStore, relayURL: relayURL) else {
                return nil
            }
            return (relayURL, cursor)
        })
    }

    private static func loadCursor(
        accountID: String?,
        eventStore: NostrEventStore?,
        relayURL: String
    ) -> NostrSyncCursorRecord? {
        guard let accountID else { return nil }
        return try? eventStore?.syncCursor(accountID: accountID, timelineKey: "home", relayURL: relayURL)
    }

    private static func loadRecentActivity(
        accountID: String?,
        eventStore: NostrEventStore?,
        relays: [RelayDescriptor]
    ) -> [RelayActivityItem] {
        guard let accountID,
              let records = try? eventStore?.relaySyncEvents(accountID: accountID, timelineKey: "home", limit: 12),
              !records.isEmpty
        else {
            return relays.prefix(3).map { RelayActivityItem(relay: $0) }
        }

        return records.map(RelayActivityItem.init(record:))
    }

    private static func loadOutboxSummary(
        accountID: String?,
        eventStore: NostrEventStore?
    ) -> OutboxStatusSummary {
        guard let accountID,
              let records = try? eventStore?.outboxEvents(accountID: accountID, limit: 50)
        else {
            return .empty
        }
        return OutboxStatusSummary(records: records)
    }
}

private struct RelayActivityItem: Identifiable, Equatable {
    let id: String
    let relayURL: String
    let host: String
    let kind: NostrRelaySyncEventKind?
    let occurredAt: Int?
    let message: String
    let eventCount: Int

    init(record: NostrRelaySyncEventRecord) {
        id = "\(record.relayURL)-\(record.occurredAt)-\(record.kind.rawValue)-\(record.subscriptionID ?? "")-\(record.message ?? "")"
        relayURL = record.relayURL
        host = Self.host(from: record.relayURL)
        kind = record.kind
        occurredAt = record.occurredAt
        eventCount = record.eventCount
        message = Self.message(for: record)
    }

    init(relay: RelayDescriptor) {
        id = relay.url
        relayURL = relay.url
        host = relay.host
        kind = nil
        occurredAt = nil
        eventCount = 0
        message = relay.lastMessage
    }

    var tint: Color {
        switch kind {
        case .connected, .eose:
            .green
        case .reconnect:
            .orange
        case .authRequired:
            .purple
        case .paymentRequired:
            .yellow
        case .closed, .timeout, .partialFailure, .rejected, .suspended:
            .red
        default:
            .secondary
        }
    }

    private static func message(for record: NostrRelaySyncEventRecord) -> String {
        if let message = record.message, !message.isEmpty {
            return message
        }
        if record.eventCount > 0 {
            return "\(record.eventCount) events"
        }
        return record.kind.rawValue
    }

    private static func host(from relayURL: String) -> String {
        relayURL
            .replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
    }
}

private struct OutboxStatusSummary: Equatable {
    let pending: Int
    let publishing: Int
    let partial: Int
    let failed: Int
    let published: Int
    let recentStatuses: [String]

    static let empty = OutboxStatusSummary(
        pending: 0,
        publishing: 0,
        partial: 0,
        failed: 0,
        published: 0,
        recentStatuses: []
    )

    init(records: [NostrOutboxEventRecord]) {
        pending = records.filter { $0.status == NostrOutboxStatus.pending }.count
        publishing = records.filter { $0.status == NostrOutboxStatus.publishing }.count
        partial = records.filter { $0.status == NostrOutboxStatus.partial }.count
        failed = records.filter { $0.status == NostrOutboxStatus.failed }.count
        published = records.filter { $0.status == NostrOutboxStatus.published }.count
        recentStatuses = records.prefix(3).map(\.status)
    }

    private init(
        pending: Int,
        publishing: Int,
        partial: Int,
        failed: Int,
        published: Int,
        recentStatuses: [String]
    ) {
        self.pending = pending
        self.publishing = publishing
        self.partial = partial
        self.failed = failed
        self.published = published
        self.recentStatuses = recentStatuses
    }

    var activeCount: Int {
        pending + publishing + partial + failed
    }

    var title: String {
        activeCount == 0 ? "No queued publishes" : "\(activeCount) publish updates"
    }

    var detail: String {
        if activeCount == 0 {
            return "Posts can render while relay publish results continue in the background."
        }
        return [
            pending > 0 ? "\(pending) pending" : nil,
            publishing > 0 ? "\(publishing) publishing" : nil,
            partial > 0 ? "\(partial) partial" : nil,
            failed > 0 ? "\(failed) failed" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " / ")
    }
}

private struct RelayStatusSummaryCard: View {
    let connected: Int
    let planned: Int
    let relays: [RelayDescriptor]

    private var progress: Double {
        guard planned > 0 else { return 0 }
        return min(Double(connected) / Double(planned), 1)
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [.astrenzaAccent, .cyan, .astrenzaAccent], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(connected)")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                    Text("/ \(planned)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 10) {
                Text("Connected Relays")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                Text("NIP-65 relays, DM inbox relays, and manual fallback relays are tracked separately.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    RelayCountPill(title: "read", count: relays.filter { $0.usage.contains(.read) }.count, tint: .cyan)
                    RelayCountPill(title: "write", count: relays.filter { $0.usage.contains(.write) }.count, tint: .green)
                    RelayCountPill(title: "dm", count: relays.filter { $0.usage.contains(.dm) }.count, tint: .purple)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct RelayCountPill: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        Text("\(count) \(title)")
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

private struct RelayConnectionLogCard: View {
    let activities: [RelayActivityItem]
    let relays: [RelayDescriptor]
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recent Activity", systemImage: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Spacer()
                Text(isLive ? "DB history" : "mock live")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(activities.prefix(5)) { activity in
                HStack(spacing: 10) {
                    Circle()
                        .fill(activity.tint)
                        .frame(width: 8, height: 8)
                    Text(activity.host)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .lineLimit(1)
                    Text(activity.message)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if activity.eventCount > 0 {
                        Text("+\(activity.eventCount)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct OutboxStatusCard: View {
    let summary: OutboxStatusSummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: summary.activeCount == 0 ? "tray" : "paperplane.circle.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(summary.failed > 0 ? .red : Color.astrenzaAccent)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text(summary.detail)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if summary.activeCount > 0 {
                HStack(spacing: -5) {
                    ForEach(Array(summary.recentStatuses.enumerated()), id: \.offset) { _, status in
                        Circle()
                            .fill(tint(for: status))
                            .frame(width: 12, height: 12)
                            .overlay {
                                Circle().stroke(Color.astrenzaBackground, lineWidth: 2)
                            }
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    private func tint(for status: String) -> Color {
        switch status {
        case NostrOutboxStatus.published:
            .green
        case NostrOutboxStatus.partial:
            .yellow
        case NostrOutboxStatus.failed:
            .red
        case NostrOutboxStatus.publishing:
            .cyan
        default:
            .astrenzaAccent
        }
    }
}

private struct RelayStatusRow: View {
    let relay: RelayDescriptor
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: relay.status.icon)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(relay.status.tint)
                .frame(width: 42, height: 42)
                .background(relay.status.tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(relay.displayName)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .lineLimit(1)
                    Text(relay.source.rawValue)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                Text(relay.url)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let runtimeState = relay.runtimeState {
                    Text("Runtime: \(runtimeState.displayText)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(runtimeState.tint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(relay.status.rawValue)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(relay.status.tint)
                Text(relay.pingMilliseconds.map { "\($0) ms" } ?? "no ping")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(isSelected ? Color.white.opacity(0.13) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? Color.astrenzaAccent.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct RelayInfoPanel: View {
    let relay: RelayDescriptor

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NIP-11 INFO")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(relay.displayName)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                }
                Spacer()
                Text(relay.status.rawValue)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(relay.status.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(relay.status.tint.opacity(0.16), in: Capsule())
            }

            Text(relay.description)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, spacing: 10) {
                RelayMetricTile(title: "Received", value: relay.receivedBytes, icon: "arrow.down")
                RelayMetricTile(title: "Sent", value: relay.sentBytes, icon: "arrow.up")
                RelayMetricTile(title: "Events", value: relay.eventCount, icon: "number")
                RelayMetricTile(title: "Lifecycle", value: "\(relay.lifecycle.totalProblems)", icon: "exclamationmark.triangle")
            }

            VStack(spacing: 8) {
                RelayInfoLine(title: "Sync Range", value: relay.syncRangeDescription)
                RelayInfoLine(title: "Last EOSE", value: relay.lastEOSEDescription)
                RelayInfoLine(title: "Runtime", value: relay.runtimeStateDescription)
                RelayInfoLine(title: "Lifecycle", value: relay.lifecycle.summary)
                RelayInfoLine(title: "Software", value: [relay.software, relay.version].compactMap { $0 }.joined(separator: " "))
                RelayInfoLine(title: "Limitation", value: relay.limitation)
                RelayInfoLine(title: "Contact", value: relay.contact ?? "N/A")
                RelayInfoLine(title: "Supported NIPs", value: relay.supportedNIPs.map(String.init).joined(separator: ", "))
            }

            HStack {
                ForEach(relay.usage) { usage in
                    Label(usage.rawValue, systemImage: usage.icon)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
            .lineLimit(1)
        }
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct RelayMetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(Color.astrenzaAccent)
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .lineLimit(1)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RelayInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    RelayStatusSheetView()
}

private extension RelayDescriptor {
    var syncRangeDescription: String {
        switch (newestCreatedAt, oldestCreatedAt) {
        case let (newest?, oldest?):
            "newest \(Self.shortTimestamp(newest)) / oldest \(Self.shortTimestamp(oldest))"
        case let (newest?, nil):
            "newest \(Self.shortTimestamp(newest))"
        case let (nil, oldest?):
            "oldest \(Self.shortTimestamp(oldest))"
        case (nil, nil):
            "No cursor yet"
        }
    }

    var lastEOSEDescription: String {
        lastEOSEAt.map(Self.shortTimestamp) ?? "Not reached"
    }

    private static func shortTimestamp(_ timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    func applying(summary: NostrRelaySyncSummaryRecord?, cursor: NostrSyncCursorRecord? = nil) -> RelayDescriptor {
        guard let summary else {
            return RelayDescriptor(
                url: url,
                displayName: displayName,
                status: status,
                usage: usage,
                source: source,
                pingMilliseconds: pingMilliseconds,
                receivedBytes: receivedBytes,
                sentBytes: sentBytes,
                eventCount: eventCount,
                errorCount: errorCount,
                supportedNIPs: supportedNIPs,
                software: software,
                version: version,
                description: description,
                limitation: limitation,
                contact: contact,
                lastMessage: lastMessage,
                newestCreatedAt: cursor?.newestCreatedAt ?? newestCreatedAt,
                oldestCreatedAt: cursor?.oldestCreatedAt ?? oldestCreatedAt,
                lastEOSEAt: cursor?.lastEOSEAt ?? lastEOSEAt,
                runtimeState: runtimeState,
                lifecycle: lifecycle
            )
        }

        let errors = summary.closedCount
            + summary.timeoutCount
            + summary.partialFailureCount
            + summary.authRequiredCount
            + summary.paymentRequiredCount
            + summary.rejectedCount
            + summary.suspendedCount
        let status: RelayConnectionStatus
        if summary.lastEventKind == .authRequired {
            status = summary.isRecentlyReachable() ? .authRequired : .connecting
        } else if summary.lastEventKind == .paymentRequired {
            status = summary.isRecentlyReachable() ? .paymentRequired : .connecting
        } else if summary.lastEventKind == .rejected || summary.lastEventKind == .suspended {
            status = .offline
        } else if summary.timeoutCount > 0 && summary.lastEventKind == .timeout {
            status = .offline
        } else if summary.closedCount > 0 && summary.lastEventKind == .closed {
            status = .offline
        } else if summary.partialFailureCount > 0 && summary.lastEventKind == .partialFailure {
            status = .connecting
        } else if !summary.isRecentlyReachable() {
            status = .connecting
        } else {
            status = self.status == .connecting ? .online : self.status
        }

        return RelayDescriptor(
            url: url,
            displayName: displayName,
            status: status,
            usage: usage,
            source: source,
            pingMilliseconds: summary.averageEOSELatencyMilliseconds ?? pingMilliseconds,
            receivedBytes: receivedBytes == "pending" ? "DB history" : receivedBytes,
            sentBytes: sentBytes,
            eventCount: summary.totalEventCount > 0 ? "\(summary.totalEventCount)" : eventCount,
            errorCount: errors,
            supportedNIPs: supportedNIPs,
            software: software,
            version: version,
            description: description,
            limitation: limitation,
            contact: contact,
            lastMessage: summary.lastMessage,
            newestCreatedAt: cursor?.newestCreatedAt ?? newestCreatedAt,
            oldestCreatedAt: cursor?.oldestCreatedAt ?? oldestCreatedAt,
            lastEOSEAt: cursor?.lastEOSEAt ?? summary.lastEOSEAt ?? lastEOSEAt,
            runtimeState: runtimeState,
            lifecycle: RelayLifecycleCounts(summary: summary)
        )
    }

    var runtimeStateDescription: String {
        runtimeState?.displayText ?? "No live session"
    }

    func withRuntimeState(_ runtimeState: NostrRelayConnectionState?) -> RelayDescriptor {
        RelayDescriptor(
            url: url,
            displayName: displayName,
            status: status,
            usage: usage,
            source: source,
            pingMilliseconds: pingMilliseconds,
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            eventCount: eventCount,
            errorCount: errorCount,
            supportedNIPs: supportedNIPs,
            software: software,
            version: version,
            description: description,
            limitation: limitation,
            contact: contact,
            lastMessage: lastMessage,
            newestCreatedAt: newestCreatedAt,
            oldestCreatedAt: oldestCreatedAt,
            lastEOSEAt: lastEOSEAt,
            runtimeState: runtimeState,
            lifecycle: lifecycle
        )
    }

    func preservingConnectionState(from relay: RelayDescriptor) -> RelayDescriptor {
        RelayDescriptor(
            url: url,
            displayName: displayName,
            status: relay.status,
            usage: usage,
            source: source,
            pingMilliseconds: relay.pingMilliseconds,
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            eventCount: eventCount,
            errorCount: relay.errorCount,
            supportedNIPs: supportedNIPs,
            software: software,
            version: version,
            description: description,
            limitation: limitation,
            contact: contact,
            lastMessage: lastMessage,
            newestCreatedAt: relay.newestCreatedAt,
            oldestCreatedAt: relay.oldestCreatedAt,
            lastEOSEAt: relay.lastEOSEAt,
            runtimeState: runtimeState ?? relay.runtimeState,
            lifecycle: lifecycle
        )
    }

    static func live(url: String, information: NostrRelayInformationDocument) -> RelayDescriptor {
        let host = URL(string: url)?.host ?? url
        let software = information.software ?? "Unknown relay"
        let limitation = information.limitation?.summary ?? "No published limits"
        return RelayDescriptor(
            url: url,
            displayName: information.name ?? host,
            status: information.limitation?.authRequired == true ? .authRequired : (information.limitation?.paymentRequired == true ? .paymentRequired : .online),
            usage: [.read],
            source: .nip65,
            pingMilliseconds: nil,
            receivedBytes: "live",
            sentBytes: "live",
            eventCount: information.supportedNips.isEmpty ? "N/A" : "\(information.supportedNips.count) NIPs",
            errorCount: 0,
            supportedNIPs: information.supportedNips,
            software: software,
            version: information.version,
            description: information.description ?? "This relay publishes a NIP-11 information document.",
            limitation: limitation,
            contact: information.contact,
            lastMessage: "NIP-11 info fetched"
        )
    }

    static func liveFailure(url: String, error: Error) -> RelayDescriptor {
        RelayDescriptor(
            url: url,
            displayName: URL(string: url)?.host ?? url,
            status: .offline,
            usage: [.read],
            source: .nip65,
            pingMilliseconds: nil,
            receivedBytes: "0 B",
            sentBytes: "0 B",
            eventCount: "N/A",
            errorCount: 1,
            supportedNIPs: [],
            software: "Unavailable",
            version: nil,
            description: "Relay information could not be fetched: \(error.localizedDescription)",
            limitation: "Unknown",
            contact: nil,
            lastMessage: "NIP-11 request failed"
        )
    }
}

private extension NostrRelaySyncSummaryRecord {
    var lastMessage: String {
        switch lastEventKind {
        case .connected:
            return "Connected"
        case .eose:
            if let averageEOSELatencyMilliseconds {
                return "EOSE avg \(averageEOSELatencyMilliseconds) ms"
            }
            return "EOSE recorded"
        case .closed:
            return "Relay closed connection"
        case .timeout:
            return "Timeout recorded"
        case .partialFailure:
            return lastPartialFailureReason ?? "Partial failure recorded"
        case .authRequired:
            return "AUTH challenge required"
        case .paymentRequired:
            return "Payment required"
        case .rejected:
            return lastPartialFailureReason ?? "Relay rejected the subscription"
        case .suspended:
            return lastPartialFailureReason ?? "Relay suspended for this session"
        case .reconnect:
            return "Reconnect recorded"
        case .negentropy:
            return "NIP-77 sync recorded"
        case nil:
            return "No relay history"
        }
    }
}

private extension RelayLifecycleCounts {
    init(summary: NostrRelaySyncSummaryRecord) {
        self.init(
            reconnects: summary.reconnectCount,
            timeouts: summary.timeoutCount,
            closed: summary.closedCount,
            partialFailures: summary.partialFailureCount,
            authRequired: summary.authRequiredCount,
            paymentRequired: summary.paymentRequiredCount,
            rejected: summary.rejectedCount,
            suspended: summary.suspendedCount
        )
    }
}

private extension NostrRelayConnectionState {
    var displayText: String {
        switch self {
        case .initialized:
            "initialized"
        case .connecting:
            "connecting"
        case .connected:
            "connected"
        case .waitingForRetry:
            "waiting retry"
        case .retrying:
            "retrying"
        case .dormant:
            "dormant"
        case .error:
            "error"
        case .rejected:
            "rejected"
        case .suspended:
            "suspended"
        case .terminated:
            "terminated"
        }
    }

    var tint: Color {
        switch self {
        case .connected:
            .green
        case .connecting, .retrying, .waitingForRetry:
            .orange
        case .initialized, .dormant:
            .secondary
        case .error, .rejected, .suspended, .terminated:
            .red
        }
    }
}

private extension NostrRelayLimitation {
    var summary: String {
        var parts: [String] = []
        if authRequired == true { parts.append("AUTH required") }
        if paymentRequired == true { parts.append("Payment required") }
        if restrictedWrites == true { parts.append("Restricted writes") }
        if let maxLimit { parts.append("max limit \(maxLimit)") }
        if let maxMessageLength { parts.append("max message \(maxMessageLength) bytes") }
        return parts.isEmpty ? "No published limits" : parts.joined(separator: ", ")
    }
}
