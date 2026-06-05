import SwiftUI

struct RelayStatusSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRelay: RelayDescriptor? = RelayMockStore.relays.first

    private var connectedCount: Int {
        RelayMockStore.connectedCount
    }

    private var plannedCount: Int {
        RelayMockStore.plannedCount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RelayStatusSummaryCard(
                        connected: connectedCount,
                        planned: plannedCount,
                        relays: RelayMockStore.relays
                    )

                    RelayConnectionLogCard(relays: RelayMockStore.relays)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("RELAYS")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)

                        ForEach(RelayMockStore.relays) { relay in
                            Button {
                                withAnimation(.snappy(duration: 0.22)) {
                                    selectedRelay = relay
                                }
                            } label: {
                                RelayStatusRow(relay: relay, isSelected: relay.id == selectedRelay?.id)
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
        .preferredColorScheme(.dark)
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
    let relays: [RelayDescriptor]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recent Activity", systemImage: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Spacer()
                Text("mock live")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(relays.prefix(3)) { relay in
                HStack(spacing: 10) {
                    Circle()
                        .fill(relay.status.tint)
                        .frame(width: 8, height: 8)
                    Text(relay.host)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .lineLimit(1)
                    Text(relay.lastMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
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
                RelayMetricTile(title: "Errors", value: "\(relay.errorCount)", icon: "exclamationmark.triangle")
            }

            VStack(spacing: 8) {
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
