import SwiftUI

struct HomeTimelineChromeView: View {
    let timelineStore: NostrHomeTimelineStore
    let visibleTab: TimelineTab
    let isPostDetailPresented: Bool
    let collapseProgress: CGFloat
    let onDismissFloatingMenus: () -> Void
    let onRelayStatusTap: () -> Void
    let onSettingsTap: () -> Void
    let onSelectAccount: (String) -> Void
    let onOpenFilters: () -> Void
    @ObservedObject var sessionStore: NostrSessionStore
    @Binding var selectedTimeline: TimelineKind
    @Binding var isTimelineMenuPresented: Bool
    @Binding var isUserSwitcherPresented: Bool

    private var accountSummaries: [NostrAccountSummary] {
        _ = timelineStore.resolvedContentRevision
        return sessionStore.accountSummaries(
            eventStore: timelineStore.relayStatusEventStore
        )
    }

    private var currentAccountSummary: NostrAccountSummary? {
        guard let currentPubkey = sessionStore.account?.pubkey else {
            return nil
        }
        return accountSummaries.first { $0.id == currentPubkey }
    }

    private var relayConnectedCount: Int {
        guard sessionStore.account != nil else {
            return RelayMockStore.connectedCount
        }
        return timelineStore.relayStatusCounts.connected
    }

    private var relayPlannedCount: Int {
        guard sessionStore.account != nil else {
            return RelayMockStore.plannedCount
        }
        return timelineStore.relayStatusCounts.planned
    }

    private var isVisible: Bool {
        visibleTab == .home && !isPostDetailPresented
    }

    var body: some View {
        ZStack {
            if isVisible {
                topBar
            }

            if isVisible, timelineStore.visibleUnreadBadgeCount > 0 {
                unreadBadge
            }

            if isVisible, timelineStore.filterStatus.isVisible {
                filterIndicator
            }
        }
    }

    private var topBar: some View {
        VStack {
            HomeTimelineTopBar(
                visibleTab: visibleTab,
                selectedTimeline: $selectedTimeline,
                isTimelineMenuPresented: $isTimelineMenuPresented,
                isUserSwitcherPresented: $isUserSwitcherPresented,
                collapseProgress: collapseProgress,
                onDismissFloatingMenus: onDismissFloatingMenus,
                onRelayStatusTap: onRelayStatusTap,
                onSettingsTap: onSettingsTap,
                currentAccount: currentAccountSummary,
                accounts: accountSummaries,
                onSelectAccount: onSelectAccount,
                onAddAccount: onSettingsTap,
                relayConnectedCount: relayConnectedCount,
                relayPlannedCount: relayPlannedCount,
                isRelayProcessing: timelineStore.isRelayProcessing,
                relayProcessingLabel:
                    timelineStore.activityStatus?.compactLabel
            )
            .zIndex(30)

            Spacer(minLength: 0)
        }
    }

    private var unreadBadge: some View {
        HomeUnreadBadge(
            count: timelineStore.visibleUnreadBadgeCount,
            onTap: dismissUnreadBadge
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topTrailing
        )
        .padding(.top, 88)
        .padding(.trailing, 22)
    }

    private var filterIndicator: some View {
        HomeFilterIndicator(
            status: timelineStore.filterStatus,
            onOpenFilters: onOpenFilters,
            onClear: timelineStore.suspendTimelineFilters,
            onResume: timelineStore.resumeTimelineFilters
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding(.top, 72)
        .padding(.leading, 16)
        .transition(
            .scale(scale: 0.92, anchor: .topLeading)
                .combined(with: .opacity)
        )
        .zIndex(32)
    }

    private func dismissUnreadBadge() {
        timelineStore.dismissUnreadBadge()
        onDismissFloatingMenus()
    }
}
