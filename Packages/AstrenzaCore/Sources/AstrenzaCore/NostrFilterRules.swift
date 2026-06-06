import Foundation

public enum NostrFilterRuleKind: String, Codable, Equatable, Sendable {
    case mutedPubkey
    case mutedHashtag
    case keyword
    case regex
    case mutedKind
    case relayMute
}

public enum NostrFilterRulePresentation: String, Codable, Equatable, Sendable {
    case maskWithWarning
    case hide
}

public enum NostrFilterTimelineScope: String, Codable, CaseIterable, Equatable, Sendable {
    case home
    case mentions
    case threads
    case lists
    case publicTimelines
}

public struct NostrFilterRuleRecord: Codable, Equatable, Sendable {
    public let ruleID: String
    public let accountID: String
    public let kind: NostrFilterRuleKind
    public let value: String
    public let expiresAt: Int?
    public let isEnabled: Bool
    public let presentation: NostrFilterRulePresentation
    public let scopes: Set<NostrFilterTimelineScope>
    public let createdAt: Int
    public let updatedAt: Int

    public init(
        ruleID: String,
        accountID: String,
        kind: NostrFilterRuleKind,
        value: String,
        expiresAt: Int? = nil,
        isEnabled: Bool = true,
        presentation: NostrFilterRulePresentation = .maskWithWarning,
        scopes: Set<NostrFilterTimelineScope> = [.home, .lists, .publicTimelines],
        createdAt: Int,
        updatedAt: Int
    ) {
        self.ruleID = ruleID
        self.accountID = accountID
        self.kind = kind
        self.value = value
        self.expiresAt = expiresAt
        self.isEnabled = isEnabled
        self.presentation = presentation
        self.scopes = scopes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func applies(to timeline: NostrFilterTimelineScope) -> Bool {
        scopes.contains(timeline)
    }
}

public enum NostrFilterMatchReason: Equatable, Sendable {
    case mutedPubkey(String)
    case mutedHashtag(String)
    case keyword(String)
    case regex(String)
    case mutedKind(Int)
    case relayMute(String)
}

public struct NostrFilterMatch: Equatable, Sendable {
    public let rule: NostrFilterRuleRecord
    public let reason: NostrFilterMatchReason

    public init(rule: NostrFilterRuleRecord, reason: NostrFilterMatchReason) {
        self.rule = rule
        self.reason = reason
    }
}

public struct NostrFilterRuleSet: Equatable, Sendable {
    public let rules: [NostrFilterRuleRecord]

    public init(rules: [NostrFilterRuleRecord]) {
        self.rules = rules
    }

    public static func publicMuteRules(
        accountID: String,
        items: [NostrListItemRecord],
        updatedAt: Int
    ) -> [NostrFilterRuleRecord] {
        items.compactMap { item in
            guard let kind = filterKind(forNIP51ItemType: item.itemType) else { return nil }
            return NostrFilterRuleRecord(
                ruleID: "nip51:\(item.listID):\(item.itemKey)",
                accountID: accountID,
                kind: kind,
                value: item.value,
                createdAt: updatedAt,
                updatedAt: updatedAt
            )
        }
    }

    public func match(
        event: NostrEvent,
        timeline: NostrFilterTimelineScope = .home,
        now: Int
    ) -> NostrFilterMatchReason? {
        matchDetail(event: event, timeline: timeline, now: now)?.reason
    }

    public func matchDetail(
        event: NostrEvent,
        timeline: NostrFilterTimelineScope = .home,
        now: Int
    ) -> NostrFilterMatch? {
        guard let rule = matchingRule(for: event, timeline: timeline, now: now) else { return nil }
        return NostrFilterMatch(rule: rule, reason: matchReason(rule: rule, event: event))
    }

    public func matchingRule(
        for event: NostrEvent,
        timeline: NostrFilterTimelineScope = .home,
        now: Int
    ) -> NostrFilterRuleRecord? {
        activeRules(now: now).first { rule in
            rule.applies(to: timeline) && matches(rule: rule, event: event)
        }
    }

    public func matchingCount(
        events: [NostrEvent],
        timeline: NostrFilterTimelineScope = .home,
        now: Int
    ) -> Int {
        events.filter { matchingRule(for: $0, timeline: timeline, now: now) != nil }.count
    }

    private func activeRules(now: Int) -> [NostrFilterRuleRecord] {
        rules.filter { rule in
            rule.isEnabled && rule.expiresAt.map { $0 > now } != false
        }
    }

    private func matches(rule: NostrFilterRuleRecord, event: NostrEvent) -> Bool {
        switch rule.kind {
        case .mutedPubkey:
            event.pubkey == rule.value
        case .mutedHashtag:
            event.hashtagValues.contains(rule.value.lowercased())
        case .keyword:
            event.content.localizedCaseInsensitiveContains(rule.value)
        case .regex:
            matchesRegex(rule.value, content: event.content)
        case .mutedKind:
            Int(rule.value) == event.kind
        case .relayMute:
            false
        }
    }

    private func matchReason(rule: NostrFilterRuleRecord, event: NostrEvent) -> NostrFilterMatchReason {
        switch rule.kind {
        case .mutedPubkey:
            .mutedPubkey(rule.value)
        case .mutedHashtag:
            .mutedHashtag(rule.value)
        case .keyword:
            .keyword(rule.value)
        case .regex:
            .regex(rule.value)
        case .mutedKind:
            .mutedKind(event.kind)
        case .relayMute:
            .relayMute(rule.value)
        }
    }

    private func matchesRegex(_ pattern: String, content: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return expression.firstMatch(in: content, range: range) != nil
    }

    private static func filterKind(forNIP51ItemType itemType: String) -> NostrFilterRuleKind? {
        switch itemType {
        case "pubkey":
            .mutedPubkey
        case "hashtag":
            .mutedHashtag
        case "word":
            .keyword
        default:
            nil
        }
    }
}

private extension NostrEvent {
    var hashtagValues: Set<String> {
        Set(tags.compactMap { tag in
            guard tag.first == "t", tag.count > 1 else { return nil }
            return tag[1].lowercased()
        })
    }
}
