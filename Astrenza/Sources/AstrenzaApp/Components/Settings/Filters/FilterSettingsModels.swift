import AstrenzaCore
import SwiftUI

enum FilterEditorKind: String, Identifiable {
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

enum FilterApplicationScope: String, CaseIterable, Identifiable {
    case home = "Home"
    case mentions = "Mentions & Notifications"
    case threads = "Threads"
    case lists = "Lists"
    case publicTimelines = "Public Timelines"

    var id: String { rawValue }

    var coreScope: NostrFilterTimelineScope {
        switch self {
        case .home: .home
        case .mentions: .mentions
        case .threads: .threads
        case .lists: .lists
        case .publicTimelines: .publicTimelines
        }
    }

    init(coreScope: NostrFilterTimelineScope) {
        switch coreScope {
        case .home:
            self = .home
        case .mentions:
            self = .mentions
        case .threads:
            self = .threads
        case .lists:
            self = .lists
        case .publicTimelines:
            self = .publicTimelines
        }
    }
}

enum FilterDuration: String, CaseIterable, Identifiable {
    case forever = "Forever"
    case oneDay = "24 Hours"
    case sevenDays = "7 Days"
    case thirtyDays = "30 Days"

    var id: String { rawValue }

    func expiresAt(from now: Int) -> Int? {
        switch self {
        case .forever:
            nil
        case .oneDay:
            now + 86_400
        case .sevenDays:
            now + 604_800
        case .thirtyDays:
            now + 2_592_000
        }
    }

    init(expiresAt: Int?, referenceTime: Int) {
        guard let expiresAt else {
            self = .forever
            return
        }

        let delta = max(0, expiresAt - referenceTime)
        if delta <= 86_400 {
            self = .oneDay
        } else if delta <= 604_800 {
            self = .sevenDays
        } else {
            self = .thirtyDays
        }
    }
}

struct FilterCandidateUser: Identifiable {
    let id: String
    let displayName: String
    let npub: String
    let nip05: String
    let avatar: AvatarStyle

    init(id: String, displayName: String, npub: String, nip05: String, avatar: AvatarStyle) {
        self.id = id
        self.displayName = displayName
        self.npub = npub
        self.nip05 = nip05
        self.avatar = avatar
    }

    init(profile: NostrProfileSearchResult) {
        let hasImage = profile.pictureURL != nil
        self.init(
            id: profile.pubkey,
            displayName: profile.displayName ?? "Unknown User",
            npub: profile.pubkey.abbreviatedMiddle,
            nip05: profile.nip05 ?? "NIP-05 not cached",
            avatar: AvatarStyle(
                primary: .purple,
                secondary: .blue,
                symbolName: "person.crop.circle.fill",
                pictureState: hasImage ? .resolved : .missing,
                placeholderSeed: profile.pubkey,
                imageURL: profile.pictureURL
            )
        )
    }

    static func directCandidate(from input: String) -> FilterCandidateUser? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pubkey: String
        let label: String
        if NostrHex.isLowercaseHex(trimmed, byteCount: 32) {
            pubkey = trimmed
            label = "Direct pubkey"
        } else if let decoded = try? NostrNIP19.publicKeyHex(from: trimmed) {
            pubkey = decoded
            label = "Direct npub"
        } else {
            return nil
        }

        return FilterCandidateUser(
            id: pubkey,
            displayName: "Nostr User",
            npub: trimmed.abbreviatedMiddle,
            nip05: label,
            avatar: AvatarStyle(
                primary: .indigo,
                secondary: .purple,
                symbolName: "person.crop.circle.fill",
                pictureState: .missing,
                placeholderSeed: pubkey
            )
        )
    }

    static func filteredCandidates(
        _ candidates: [FilterCandidateUser],
        query input: String
    ) -> [FilterCandidateUser] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        var matches = candidates.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.nip05.localizedCaseInsensitiveContains(query)
                || $0.npub.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
        if let directCandidate = directCandidate(from: query),
           !matches.contains(where: { $0.id == directCandidate.id }) {
            matches.append(directCandidate)
        }
        return matches
    }

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

struct FilterEditorDraft: Identifiable {
    static let potentialSpamRuleIDPrefix = "local:custom:potential-spam:"
    private static let potentialSpamPattern = "(?i)\\b(airdrop|giveaway|free\\s+crypto|limited\\s+offer)\\b"

    let id = UUID()
    let kind: FilterEditorKind
    var value: String
    var isEnabled: Bool
    var masksWithWarning: Bool
    var selectedScopes: Set<FilterApplicationScope>
    var duration: FilterDuration
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
            duration: .forever,
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
            duration: .forever,
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
            duration: .forever,
            selectedUser: nil,
            matchingCount: 0,
            totalCount: 3_944
        )
    }

    static func potentialSpam(
        accountID: String,
        existing: NostrFilterRuleRecord?,
        matchingCount: Int = 0,
        totalCount: Int = 0
    ) -> FilterEditorDraft {
        FilterEditorDraft(
            kind: .potentialSpam,
            value: potentialSpamPattern,
            isEnabled: existing?.isEnabled ?? false,
            masksWithWarning: existing?.presentation != .hide,
            selectedScopes: existing.map(scopeSet(from:)) ?? [.home],
            duration: existing.map { FilterDuration(expiresAt: $0.expiresAt, referenceTime: $0.updatedAt) } ?? .forever,
            selectedUser: nil,
            matchingCount: matchingCount,
            totalCount: totalCount
        )
    }

    static func existing(
        rule: NostrFilterRuleRecord,
        selectedUser: FilterCandidateUser? = nil,
        matchingCount: Int = 0,
        totalCount: Int = 0
    ) -> FilterEditorDraft {
        switch rule.kind {
        case .mutedPubkey:
            let candidate = selectedUser ?? FilterCandidateUser(
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
                masksWithWarning: rule.presentation != .hide,
                selectedScopes: scopeSet(from: rule),
                duration: FilterDuration(expiresAt: rule.expiresAt, referenceTime: rule.updatedAt),
                selectedUser: candidate,
                matchingCount: matchingCount,
                totalCount: totalCount
            )
        case .keyword:
            return FilterEditorDraft(
                kind: .keyword,
                value: rule.value,
                isEnabled: rule.isEnabled,
                masksWithWarning: rule.presentation != .hide,
                selectedScopes: scopeSet(from: rule),
                duration: FilterDuration(expiresAt: rule.expiresAt, referenceTime: rule.updatedAt),
                selectedUser: nil,
                matchingCount: matchingCount,
                totalCount: totalCount
            )
        case .mutedHashtag:
            return FilterEditorDraft(
                kind: .hashtag,
                value: rule.value,
                isEnabled: rule.isEnabled,
                masksWithWarning: rule.presentation != .hide,
                selectedScopes: scopeSet(from: rule),
                duration: FilterDuration(expiresAt: rule.expiresAt, referenceTime: rule.updatedAt),
                selectedUser: nil,
                matchingCount: matchingCount,
                totalCount: totalCount
            )
        default:
            return potentialSpam(
                accountID: rule.accountID,
                existing: rule,
                matchingCount: matchingCount,
                totalCount: totalCount
            )
        }
    }

    var canSave: Bool {
        switch kind {
        case .user:
            NostrHex.isLowercaseHex(normalizedValue, byteCount: 32)
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
            expiresAt: duration.expiresAt(from: now),
            isEnabled: isEnabled,
            presentation: masksWithWarning ? .maskWithWarning : .hide,
            scopes: Set(selectedScopes.map(\.coreScope)),
            createdAt: now,
            updatedAt: now
        )
    }

    private static func scopeSet(from rule: NostrFilterRuleRecord) -> Set<FilterApplicationScope> {
        let scopes = Set(rule.scopes.map(FilterApplicationScope.init(coreScope:)))
        return scopes.isEmpty ? [.home] : scopes
    }
}

extension String {
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

extension NostrFilterRuleKind {
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
