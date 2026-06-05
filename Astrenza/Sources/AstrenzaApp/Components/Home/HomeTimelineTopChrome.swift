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

    var body: some View {
        ZStack {
            titleControl

            HStack {
                Button(action: toggleUserSwitcher) {
                    UserSwitchButton(isExpanded: isUserSwitcherPresented)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if isUserSwitcherPresented {
                        UserSwitcherMenu(onSettingsTap: onSettingsTap)
                            .offset(y: 44)
                            .transition(.scale(scale: 0.72, anchor: .topLeading).combined(with: .opacity))
                            .zIndex(20)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onRelayStatusTap) {
                    RelayStatusRingButton(
                        connected: RelayMockStore.connectedCount,
                        planned: RelayMockStore.plannedCount,
                        collapseProgress: collapseProgress
                    )
                }
                .buttonStyle(.plain)
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
}

struct HomeUnreadBadge: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("3996")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
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
