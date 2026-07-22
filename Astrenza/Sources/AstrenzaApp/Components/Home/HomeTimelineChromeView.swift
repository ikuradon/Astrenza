import SwiftUI

struct HomeTimelineChromeView: View {
    let timelineStore: NostrHomeTimelineStore
    let visibleTab: TimelineTab
    let isPostDetailPresented: Bool
    let collapseProgress: CGFloat
    let isRealtimeModeEnabled: Bool
    let unreadPillPlacement: HomeUnreadPillPlacement
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
        sessionStore.accountSummaries(
            eventStore: timelineStore.presentationEventStore,
            metadataRevision: timelineStore.profileMetadataRevision
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

            if isVisible,
               selectedTimeline == .home,
               !isRealtimeModeEnabled,
               timelineStore.visibleUnreadBadgeCount > 0,
               let unreadPillOffsetY = unreadPillPlacement.offsetY {
                unreadBadge(offsetY: unreadPillOffsetY)
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
                isRealtimeModeEnabled: isRealtimeModeEnabled,
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

    private func unreadBadge(offsetY: CGFloat) -> some View {
        HomeUnreadBadge(
            count: timelineStore.visibleUnreadBadgeCount,
            onTap: dismissUnreadBadge
        )
        .offset(y: offsetY)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topTrailing
        )
        .padding(.top, 88)
        .padding(.trailing, AstrenzaSpacing.point22)
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
        .padding(.leading, AstrenzaSpacing.point16)
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
