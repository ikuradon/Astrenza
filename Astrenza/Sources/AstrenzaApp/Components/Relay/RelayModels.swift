import SwiftUI

struct RelayMockStore {
    static let relays: [RelayDescriptor] = [
        RelayDescriptor(
            url: "wss://relay-a.mock.example",
            displayName: "Mock Relay A",
            status: .online,
            usage: [.read, .write, .inbox],
            source: .nip65,
            pingMilliseconds: 84,
            receivedBytes: "18.4 MB",
            sentBytes: "2.1 MB",
            eventCount: "12.8K",
            errorCount: 0,
            supportedNIPs: [1, 11, 42, 65],
            software: "mock-relay",
            version: "1.9.4",
            description: "Primary home relay from the user's NIP-65 relay list.",
            limitation: "AUTH optional, 2 MB event size",
            contact: "ops@relay-a.mock.example",
            lastMessage: "EOSE received for home timeline"
        ),
        RelayDescriptor(
            url: "wss://relay-b.mock.example",
            displayName: "Mock Relay B",
            status: .connecting,
            usage: [.read, .search],
            source: .nip65,
            pingMilliseconds: 212,
            receivedBytes: "9.7 MB",
            sentBytes: "410 KB",
            eventCount: "4.1K",
            errorCount: 1,
            supportedNIPs: [1, 11, 50, 65],
            software: "strfry",
            version: "1.0.2",
            description: "Search and catch-up relay. Reconnecting after a stale cursor.",
            limitation: "paid writes disabled in mock",
            contact: "relay-b@mock.example",
            lastMessage: "REQ retry scheduled"
        ),
        RelayDescriptor(
            url: "wss://relay-c.mock.example",
            displayName: "Mock Relay C",
            status: .authRequired,
            usage: [.write, .outbox],
            source: .manual,
            pingMilliseconds: 156,
            receivedBytes: "1.2 MB",
            sentBytes: "812 KB",
            eventCount: "820",
            errorCount: 3,
            supportedNIPs: [1, 11, 42],
            software: "nostr-rs-relay",
            version: "0.9.0",
            description: "Write relay that requires NIP-42 authentication before publishing.",
            limitation: "AUTH required",
            contact: "admin@relay-c.mock.example",
            lastMessage: "AUTH challenge received"
        ),
        RelayDescriptor(
            url: "wss://relay-d.mock.example",
            displayName: "DM Relay",
            status: .online,
            usage: [.dm, .inbox],
            source: .nip17,
            pingMilliseconds: 98,
            receivedBytes: "4.8 MB",
            sentBytes: "1.4 MB",
            eventCount: "1.9K",
            errorCount: 0,
            supportedNIPs: [1, 11, 17, 44, 59],
            software: "private-relay",
            version: "2.1.0",
            description: "Inbox relay for encrypted direct messages and gift wraps.",
            limitation: "private events only",
            contact: "dm@mock.example",
            lastMessage: "Gift wrap subscription active"
        ),
        RelayDescriptor(
            url: "wss://relay-e.mock.example",
            displayName: "Muted Relay",
            status: .offline,
            usage: [.blocked],
            source: .blocked,
            pingMilliseconds: nil,
            receivedBytes: "0 B",
            sentBytes: "0 B",
            eventCount: "0",
            errorCount: 8,
            supportedNIPs: [1, 11],
            software: "unknown",
            version: nil,
            description: "Blocked because it repeatedly returned spam-heavy search results.",
            limitation: "blocked locally",
            contact: nil,
            lastMessage: "Disconnected by local policy"
        )
    ]

    static let recommended: [RelayDescriptor] = [
        RelayDescriptor(
            url: "wss://bootstrap-a.mock.example",
            displayName: "Bootstrap A",
            status: .online,
            usage: [.read, .write],
            source: .recommended,
            pingMilliseconds: 72,
            receivedBytes: "0 B",
            sentBytes: "0 B",
            eventCount: "Recommended",
            errorCount: 0,
            supportedNIPs: [1, 11, 42, 65],
            software: "recommended",
            version: nil,
            description: "Suggested fallback when NIP-65 relay list is missing.",
            limitation: "mock recommendation",
            contact: "relay@mock.example",
            lastMessage: "Ready to add"
        ),
        RelayDescriptor(
            url: "wss://bootstrap-b.mock.example",
            displayName: "Bootstrap B",
            status: .online,
            usage: [.read, .search],
            source: .recommended,
            pingMilliseconds: 120,
            receivedBytes: "0 B",
            sentBytes: "0 B",
            eventCount: "Recommended",
            errorCount: 0,
            supportedNIPs: [1, 11, 50],
            software: "recommended",
            version: nil,
            description: "Suggested search relay for profile and event discovery.",
            limitation: "mock recommendation",
            contact: nil,
            lastMessage: "Ready to add"
        )
    ]

    static var connectedCount: Int {
        relays.filter { $0.status == .online || $0.status == .authRequired }.count
    }

    static var plannedCount: Int {
        relays.count + recommended.count
    }
}

struct RelayDescriptor: Identifiable, Equatable {
    let id = UUID()
    let url: String
    let displayName: String
    let status: RelayConnectionStatus
    let usage: [RelayUsage]
    let source: RelaySource
    let pingMilliseconds: Int?
    let receivedBytes: String
    let sentBytes: String
    let eventCount: String
    let errorCount: Int
    let supportedNIPs: [Int]
    let software: String
    let version: String?
    let description: String
    let limitation: String
    let contact: String?
    let lastMessage: String

    var host: String {
        url
            .replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
    }
}

enum RelayConnectionStatus: String {
    case online = "Online"
    case connecting = "Connecting"
    case authRequired = "AUTH"
    case offline = "Offline"

    var tint: Color {
        switch self {
        case .online: .green
        case .connecting: .orange
        case .authRequired: .purple
        case .offline: .red
        }
    }

    var icon: String {
        switch self {
        case .online: "checkmark.circle.fill"
        case .connecting: "arrow.triangle.2.circlepath"
        case .authRequired: "lock.shield.fill"
        case .offline: "xmark.circle.fill"
        }
    }
}

enum RelayUsage: String, CaseIterable, Identifiable {
    case read = "Read"
    case write = "Write"
    case inbox = "Inbox"
    case outbox = "Outbox"
    case dm = "DM"
    case search = "Search"
    case blocked = "Blocked"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .read: "arrow.down.circle.fill"
        case .write: "arrow.up.circle.fill"
        case .inbox: "tray.and.arrow.down.fill"
        case .outbox: "tray.and.arrow.up.fill"
        case .dm: "lock.bubble.left.fill"
        case .search: "magnifyingglass.circle.fill"
        case .blocked: "slash.circle.fill"
        }
    }
}

enum RelaySource: String {
    case nip65 = "NIP-65"
    case nip17 = "NIP-17"
    case manual = "Manual"
    case recommended = "Recommended"
    case blocked = "Blocked"
}
