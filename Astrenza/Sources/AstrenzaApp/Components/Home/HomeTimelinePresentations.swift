import AstrenzaCore
import SwiftUI

struct HomeTimelinePresentationModifier: ViewModifier {
    @Binding var isComposerPresented: Bool
    @Binding var isSettingsPresented: Bool
    @Binding var isFiltersSettingsPresented: Bool
    @Binding var isRelayStatusPresented: Bool
    @Binding var composeSheetMode: ComposeSheetMode
    @Binding var fullscreenMedia: TimelineFullscreenMediaRequest?
    @Binding var browserDestination: TimelineBrowserDestination?
    @Binding var swipeSettings: TimelineSwipeSettings
    let relayURLs: [String]
    let relayRuntimeStates: [String: NostrRelayConnectionState]
    let accountID: String?
    let eventStore: NostrEventStore?
    let accountSummaries: [NostrAccountSummary]
    let onSelectAccount: (String) -> Void
    let onRemoveAccount: (String) -> Void
    let onAddAccount: () -> Void
    let isComposeSubmitAvailable: Bool
    let onComposeSubmit: ((ComposeSubmitRequest) async -> Bool)?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isComposerPresented) {
                ComposeSheetView(
                    mode: composeSheetMode,
                    isSubmitAvailable: isComposeSubmitAvailable,
                    onSubmit: onComposeSubmit,
                    accountID: accountID,
                    eventStore: eventStore
                )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(28)
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(onClose: {
                    isSettingsPresented = false
                }, swipeSettings: $swipeSettings, accountID: accountID, eventStore: eventStore,
                accountSummaries: accountSummaries,
                onSelectAccount: onSelectAccount,
                onRemoveAccount: onRemoveAccount,
                onAddAccount: onAddAccount)
                .presentationCornerRadius(26)
            }
            .sheet(isPresented: $isFiltersSettingsPresented) {
                NavigationStack {
                    NostrListSettingsView(accountID: accountID, eventStore: eventStore)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    isFiltersSettingsPresented = false
                                }
                            }
                        }
                }
                .presentationCornerRadius(26)
            }
            .sheet(isPresented: $isRelayStatusPresented) {
                RelayStatusSheetView(
                    relayURLs: relayURLs,
                    relayRuntimeStates: relayRuntimeStates,
                    accountID: accountID,
                    eventStore: eventStore
                )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(26)
            }
            .fullScreenCover(isPresented: isFullscreenMediaPresented) {
                if let request = fullscreenMedia {
                    TimelineFullscreenMediaViewer(
                        media: request.media,
                        initialTileIndex: request.initialTileIndex
                    ) {
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
        isFiltersSettingsPresented: Binding<Bool>,
        isRelayStatusPresented: Binding<Bool>,
        composeSheetMode: Binding<ComposeSheetMode>,
        fullscreenMedia: Binding<TimelineFullscreenMediaRequest?>,
        browserDestination: Binding<TimelineBrowserDestination?>,
        swipeSettings: Binding<TimelineSwipeSettings>,
        relayURLs: [String],
        relayRuntimeStates: [String: NostrRelayConnectionState] = [:],
        accountID: String?,
        eventStore: NostrEventStore?,
        accountSummaries: [NostrAccountSummary] = [],
        onSelectAccount: @escaping (String) -> Void = { _ in },
        onRemoveAccount: @escaping (String) -> Void = { _ in },
        onAddAccount: @escaping () -> Void = {},
        isComposeSubmitAvailable: Bool = true,
        onComposeSubmit: ((ComposeSubmitRequest) async -> Bool)? = nil
    ) -> some View {
        modifier(
            HomeTimelinePresentationModifier(
                isComposerPresented: isComposerPresented,
                isSettingsPresented: isSettingsPresented,
                isFiltersSettingsPresented: isFiltersSettingsPresented,
                isRelayStatusPresented: isRelayStatusPresented,
                composeSheetMode: composeSheetMode,
                fullscreenMedia: fullscreenMedia,
                browserDestination: browserDestination,
                swipeSettings: swipeSettings,
                relayURLs: relayURLs,
                relayRuntimeStates: relayRuntimeStates,
                accountID: accountID,
                eventStore: eventStore,
                accountSummaries: accountSummaries,
                onSelectAccount: onSelectAccount,
                onRemoveAccount: onRemoveAccount,
                onAddAccount: onAddAccount,
                isComposeSubmitAvailable: isComposeSubmitAvailable,
                onComposeSubmit: onComposeSubmit
            )
        )
    }
}
