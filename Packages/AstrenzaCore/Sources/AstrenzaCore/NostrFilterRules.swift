import Foundation

public enum NostrFilterRuleKind: String, Codable, Equatable, Sendable {
    case mutedPubkey
    case mutedHashtag
    case keyword
    case regex
    case mutedKind
    case relayMute
}

public struct NostrFilterRuleRecord: Codable, Equatable, Sendable {
    public let ruleID: String
    public let accountID: String
    public let kind: NostrFilterRuleKind
    public let value: String
    public let expiresAt: Int?
    public let isEnabled: Bool
    public let createdAt: Int
    public let updatedAt: Int

    public init(
        ruleID: String,
        accountID: String,
        kind: NostrFilterRuleKind,
        value: String,
        expiresAt: Int? = nil,
        isEnabled: Bool = true,
        createdAt: Int,
        updatedAt: Int
    ) {
        self.ruleID = ruleID
        self.accountID = accountID
        self.kind = kind
        self.value = value
        self.expiresAt = expiresAt
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum NostrFilterMatchReason: Equatable, Sendable {
    case mutedPubkey(String)
    case mutedHashtag(String)
    case keyword(String)
    case regex(String)
    case mutedKind(Int)
}

public struct NostrFilterRuleSet: Equatable, Sendable {
    public let rules: [NostrFilterRuleRecord]

    public init(rules: [NostrFilterRuleRecord]) {
        self.rules = rules
    }

    public func match(event: NostrEvent, now: Int) -> NostrFilterMatchReason? {
        for rule in activeRules(now: now) {
            switch rule.kind {
            case .mutedPubkey where event.pubkey == rule.value:
                return .mutedPubkey(rule.value)
            case .mutedHashtag where event.hashtagValues.contains(rule.value.lowercased()):
                return .mutedHashtag(rule.value)
            case .keyword where event.content.localizedCaseInsensitiveContains(rule.value):
                return .keyword(rule.value)
            case .regex where matchesRegex(rule.value, content: event.content):
                return .regex(rule.value)
            case .mutedKind where Int(rule.value) == event.kind:
                return .mutedKind(event.kind)
            default:
                continue
            }
        }
        return nil
    }

    private func activeRules(now: Int) -> [NostrFilterRuleRecord] {
        rules.filter { rule in
            rule.isEnabled && rule.expiresAt.map { $0 > now } != false
        }
    }

    private func matchesRegex(_ pattern: String, content: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return expression.firstMatch(in: content, range: range) != nil
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
