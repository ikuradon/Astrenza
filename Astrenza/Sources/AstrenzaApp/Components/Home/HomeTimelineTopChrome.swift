import SwiftUI

struct HomeTimelineTopBar: View {
    let visibleTab: TimelineTab
    @Binding var selectedTimeline: TimelineKind
    @Binding var isTimelineMenuPresented: Bool
    @Binding var isUserSwitcherPresented: Bool
    let collapseProgress: CGFloat
    let onDismissFloatingMenus: () -> Void
    let onRelayStatusTap: () -> Void
    let onSettingsTap: () -> Void
    let currentAccount: NostrAccountSummary?
    let accounts: [NostrAccountSummary]
    let onSelectAccount: (String) -> Void
    let onAddAccount: () -> Void
    let relayConnectedCount: Int
    let relayPlannedCount: Int
    let isRelayProcessing: Bool

    var body: some View {
        ZStack {
            titleControl

            HStack {
                Button(action: toggleUserSwitcher) {
                    UserSwitchButton(isExpanded: isUserSwitcherPresented, account: currentAccount)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if isUserSwitcherPresented {
                        UserSwitcherMenu(
                            accounts: accounts,
                            onSelectAccount: selectAccount,
                            onAddAccount: onAddAccount,
                            onSettingsTap: onSettingsTap
                        )
                            .offset(y: 44)
                            .transition(.scale(scale: 0.72, anchor: .topLeading).combined(with: .opacity))
                            .zIndex(20)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onRelayStatusTap) {
                    RelayStatusRingButton(
                        connected: relayConnectedCount,
                        planned: relayPlannedCount,
                        collapseProgress: collapseProgress,
                        isProcessing: isRelayProcessing
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .accessibilityIdentifier("home.relay_status.button")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var titleControl: some View {
        if visibleTab == .home {
            Button(action: toggleTimelineMenu) {
                HStack(spacing: 7) {
                    Text(selectedTimeline.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .rotationEffect(.degrees(isTimelineMenuPresented ? 180 : 0))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .contentShape(Capsule())
                .astrenzaGlass(tint: Color.white.opacity(0.04), in: Capsule())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                if isTimelineMenuPresented {
                    TimelineSwitcherMenu(selected: $selectedTimeline)
                        .offset(y: 34)
                        .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
        } else {
            Text(visibleTab.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .astrenzaGlass(tint: Color.white.opacity(0.04), in: Capsule())
        }
    }

    private func toggleUserSwitcher() {
        withAnimation(.spring(duration: 0.32, bounce: 0.22)) {
            isUserSwitcherPresented.toggle()
            isTimelineMenuPresented = false
        }
    }

    private func toggleTimelineMenu() {
        withAnimation(.snappy(duration: 0.18)) {
            isTimelineMenuPresented.toggle()
            isUserSwitcherPresented = false
        }
    }

    private func selectAccount(_ pubkey: String) {
        onSelectAccount(pubkey)
        withAnimation(.spring(duration: 0.24, bounce: 0.14)) {
            isUserSwitcherPresented = false
        }
    }
}

struct HomeUnreadBadge: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("3996")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.astrenzaAccent, in: Capsule())
                .shadow(color: Color.astrenzaAccent.opacity(0.18), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("3996 unread posts")
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: UnreadBadgeFramePreferenceKey.self,
                    value: proxy.frame(in: .named("homeTimelineChrome"))
                )
            }
        }
    }
}

struct HomeFilterIndicator: View {
    let status: TimelineFilterStatus
    let onOpenFilters: () -> Void
    let onClear: () -> Void
    let onResume: () -> Void

    private var title: String {
        if status.isSuspended {
            return "Filters Off"
        }
        let count = status.matchedPostCount
        return count == 1 ? "1 filtered" : "\(count) filtered"
    }

    private var subtitle: String {
        if status.isSuspended {
            return "\(status.activeRuleCount) rules paused"
        }
        return "\(status.activeRuleCount) active rules"
    }

    private var controlIcon: String {
        status.isSuspended ? "arrow.counterclockwise.circle.fill" : "xmark.circle.fill"
    }

    private var controlLabel: String {
        status.isSuspended ? "Resume filters" : "Temporarily clear filters"
    }

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onOpenFilters) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        Text(subtitle)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(status.isSuspended ? .secondary : Color.astrenzaAccent)
                .padding(.leading, 12)
                .padding(.vertical, 7)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(status.isSuspended ? "Filters are paused" : "\(status.matchedPostCount) filtered posts")

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 24)

            Button(action: status.isSuspended ? onResume : onClear) {
                Image(systemName: controlIcon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(status.isSuspended ? Color.astrenzaAccent : .secondary)
                    .frame(width: 30, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controlLabel)
        }
        .padding(.trailing, 7)
        .astrenzaGlass(tint: Color.white.opacity(0.05), in: Capsule())
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }
}
