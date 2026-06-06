import SwiftUI

struct HomeTimelinePresentationModifier: ViewModifier {
    @Binding var isComposerPresented: Bool
    @Binding var isSettingsPresented: Bool
    @Binding var isRelayStatusPresented: Bool
    @Binding var composeSheetMode: ComposeSheetMode
    @Binding var fullscreenMedia: TimelineMedia?
    @Binding var browserDestination: TimelineBrowserDestination?
    @Binding var swipeSettings: TimelineSwipeSettings
    let relayURLs: [String]

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isComposerPresented) {
                ComposeSheetView(mode: composeSheetMode)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(28)
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(onClose: {
                    isSettingsPresented = false
                }, swipeSettings: $swipeSettings)
                .presentationCornerRadius(26)
            }
            .sheet(isPresented: $isRelayStatusPresented) {
                RelayStatusSheetView(relayURLs: relayURLs)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(26)
            }
            .fullScreenCover(isPresented: isFullscreenMediaPresented) {
                if let media = fullscreenMedia {
                    TimelineFullscreenMediaViewer(media: media) {
                        fullscreenMedia = nil
                    }
                }
            }
            .sheet(item: $browserDestination) { destination in
                TimelineInAppBrowserView(url: destination.url)
                    .ignoresSafeArea()
            }
    }

    private var isFullscreenMediaPresented: Binding<Bool> {
        Binding(
            get: { fullscreenMedia != nil },
            set: { isPresented in
                if !isPresented {
                    fullscreenMedia = nil
                }
            }
        )
    }
}

extension View {
    func homeTimelinePresentations(
        isComposerPresented: Binding<Bool>,
        isSettingsPresented: Binding<Bool>,
        isRelayStatusPresented: Binding<Bool>,
        composeSheetMode: Binding<ComposeSheetMode>,
        fullscreenMedia: Binding<TimelineMedia?>,
        browserDestination: Binding<TimelineBrowserDestination?>,
        swipeSettings: Binding<TimelineSwipeSettings>,
        relayURLs: [String]
    ) -> some View {
        modifier(
            HomeTimelinePresentationModifier(
                isComposerPresented: isComposerPresented,
                isSettingsPresented: isSettingsPresented,
                isRelayStatusPresented: isRelayStatusPresented,
                composeSheetMode: composeSheetMode,
                fullscreenMedia: fullscreenMedia,
                browserDestination: browserDestination,
                swipeSettings: swipeSettings,
                relayURLs: relayURLs
            )
        )
    }
}
