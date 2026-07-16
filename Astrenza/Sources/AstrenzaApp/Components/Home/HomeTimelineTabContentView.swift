import SwiftUI

struct HomeTimelineTabContentView<
    TimelineContent: View,
    ProfileContent: View
>: View {
    let timelineStore: NostrHomeTimelineStore
    let minimizeDirection: TabBarMinimizeDirection
    let isTabBarHidden: Bool
    let isHomeReturnMode: Bool
    let timelineList: TimelineContent
    let profileView: ProfileContent
    let onMinimizeDirectionChanged: (TabBarMinimizeDirection) -> Void
    let onHomeRetap: () -> Void
    let onComposeTap: () -> Void
    @Binding var selectedTab: TimelineTab
    @Binding var previousTab: TimelineTab

    var body: some View {
        UIKitTimelineTabView(
            selectedTab: $selectedTab,
            previousTab: $previousTab,
            minimizeDirection: minimizeDirection,
            isTabBarHidden: isTabBarHidden,
            hasUnmaterializedHomeEvents:
                timelineStore.unmaterializedNewCount > 0,
            isHomeReturnMode: isHomeReturnMode,
            timelineList: timelineList,
            profileView: profileView,
            onMinimizeDirectionChanged: onMinimizeDirectionChanged,
            onHomeRetap: onHomeRetap,
            onComposeTap: onComposeTap
        )
    }
}
