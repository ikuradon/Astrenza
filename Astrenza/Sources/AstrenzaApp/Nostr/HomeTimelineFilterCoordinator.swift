import AstrenzaCore
import Foundation

struct HomeTimelineFilterProjection: Equatable {
    let effectiveRuleSet: NostrFilterRuleSet?
    let status: TimelineFilterStatus
}

@MainActor
final class HomeTimelineFilterCoordinator {
    private let eventStore: NostrEventStore?
    private var isSuspended = false

    init(eventStore: NostrEventStore?) {
        self.eventStore = eventStore
    }

    func projection(
        accountID: String?,
        events: [NostrEvent],
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> HomeTimelineFilterProjection {
        let rules = homeRules(accountID: accountID, updatedAt: now)
        let configuredRuleSet = rules.isEmpty ? nil : NostrFilterRuleSet(rules: rules)
        return HomeTimelineFilterProjection(
            effectiveRuleSet: isSuspended ? nil : configuredRuleSet,
            status: status(
                configuredRuleSet: configuredRuleSet,
                events: events,
                now: now
            )
        )
    }

    func effectiveRuleSet(
        accountID: String?,
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> NostrFilterRuleSet? {
        guard !isSuspended else { return nil }
        let rules = homeRules(accountID: accountID, updatedAt: now)
        guard !rules.isEmpty else { return nil }
        return NostrFilterRuleSet(rules: rules)
    }

    @discardableResult
    func suspend() -> Bool {
        guard !isSuspended else { return false }
        isSuspended = true
        return true
    }

    @discardableResult
    func resume() -> Bool {
        guard isSuspended else { return false }
        isSuspended = false
        return true
    }

    func reset() {
        isSuspended = false
    }

    private func homeRules(
        accountID: String?,
        updatedAt: Int
    ) -> [NostrFilterRuleRecord] {
        guard let accountID, let eventStore else { return [] }

        var rules = ((try? eventStore.filterRules(accountID: accountID)) ?? [])
            .filter { $0.applies(to: .home) }
        rules.append(
            contentsOf: NostrFilterRuleSet.publicMuteRules(
                accountID: accountID,
                items: cachedPublicMuteItems(
                    accountID: accountID,
                    eventStore: eventStore
                ),
                updatedAt: updatedAt
            )
        )
        return rules
    }

    private func status(
        configuredRuleSet: NostrFilterRuleSet?,
        events: [NostrEvent],
        now: Int
    ) -> TimelineFilterStatus {
        guard let configuredRuleSet else {
            return TimelineFilterStatus(isSuspended: isSuspended)
        }

        var status = TimelineFilterStatus(
            activeRuleCount: configuredRuleSet.rules.count,
            isSuspended: isSuspended
        )
        guard !isSuspended else { return status }

        for event in events {
            guard let match = configuredRuleSet.matchDetail(
                event: event,
                timeline: .home,
                now: now
            ) else { continue }
            switch match.rule.presentation {
            case .maskWithWarning:
                status.warningMatchCount += 1
            case .hide:
                status.hiddenMatchCount += 1
            }
        }
        return status
    }

    private func cachedPublicMuteItems(
        accountID: String,
        eventStore: NostrEventStore
    ) -> [NostrListItemRecord] {
        guard let summaries = try? eventStore.listSummaries(accountID: accountID) else {
            return []
        }
        return summaries
            .filter { $0.kind == 10_000 }
            .flatMap { summary in
                (try? eventStore.listItems(listID: summary.listID)) ?? []
            }
    }
}
