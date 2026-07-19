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
    let relayProcessingLabel: String?

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
                        isProcessing: isRelayProcessing,
                        processingLabel: relayProcessingLabel
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .accessibilityIdentifier("home.relay_status.button")
            }
        }
        .padding(.horizontal, AstrenzaSpacing.point18)
        .padding(.top, AstrenzaSpacing.point12)
        .padding(.bottom, AstrenzaSpacing.point8)
    }

    @ViewBuilder
    private var titleControl: some View {
        if visibleTab == .home {
            Button(action: toggleTimelineMenu) {
                HStack(spacing: AstrenzaSpacing.point7) {
                    Text(selectedTimeline.title)
                        .font(.astrenza(.point20, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.astrenza(.point15, weight: .bold))
                        .rotationEffect(.degrees(isTimelineMenuPresented ? 180 : 0))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, AstrenzaSpacing.point14)
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
                .font(.astrenza(.point20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, AstrenzaSpacing.point14)
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
        withAnimation(.snappy(duration: AstrenzaMotion.fast)) {
            isTimelineMenuPresented.toggle()
            isUserSwitcherPresented = false
        }
    }

    private func selectAccount(_ pubkey: String) {
        onSelectAccount(pubkey)
        withAnimation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.14)) {
            isUserSwitcherPresented = false
        }
    }
}

struct HomeUnreadBadge: View {
    let count: Int
    let onTap: () -> Void

    private var displayCount: String {
        count > 999 ? "999+" : "\(count)"
    }

    var body: some View {
        Button(action: onTap) {
            Text(displayCount)
                .font(.astrenza(.point11, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, AstrenzaSpacing.point8)
                .padding(.vertical, AstrenzaSpacing.point4)
                .background(Color.astrenzaAccent, in: Capsule())
                .shadow(color: Color.astrenzaAccent.opacity(0.18), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayCount) unread posts")
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
        HStack(spacing: AstrenzaSpacing.point9) {
            Button(action: onOpenFilters) {
                HStack(spacing: AstrenzaSpacing.point8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.astrenza(.point15, weight: .bold))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.astrenza(.point13, weight: .heavy, design: .rounded))
                        Text(subtitle)
                            .font(.astrenza(.point10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(status.isSuspended ? .secondary : Color.astrenzaAccent)
                .padding(.leading, AstrenzaSpacing.point12)
                .padding(.vertical, AstrenzaSpacing.point7)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(status.isSuspended ? "Filters are paused" : "\(status.matchedPostCount) filtered posts")

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 24)

            Button(action: status.isSuspended ? onResume : onClear) {
                Image(systemName: controlIcon)
                    .font(.astrenza(.point17, weight: .bold))
                    .foregroundStyle(status.isSuspended ? Color.astrenzaAccent : .secondary)
                    .frame(width: 30, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controlLabel)
        }
        .padding(.trailing, AstrenzaSpacing.point7)
        .astrenzaGlass(tint: Color.white.opacity(0.05), in: Capsule())
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }
}
