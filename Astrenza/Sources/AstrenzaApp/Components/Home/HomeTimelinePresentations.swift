import AstrenzaCore
import SwiftUI

struct HomeTimelinePresentationBindings {
    let isComposerPresented: Binding<Bool>
    let isSettingsPresented: Binding<Bool>
    let isFiltersSettingsPresented: Binding<Bool>
    let isRelayStatusPresented: Binding<Bool>
    let composeSheetMode: Binding<ComposeSheetMode>
    let fullscreenMedia: Binding<TimelineFullscreenMediaRequest?>
    let browserDestination: Binding<TimelineBrowserDestination?>
    let swipeSettings: Binding<TimelineSwipeSettings>
}

struct HomeTimelinePresentationActions {
    let onSelectAccount: (String) -> Void
    let onRemoveAccount: (String) -> Void
    let onAddAccount: () -> Void
    let onComposeSubmit: ((ComposeSubmitRequest) async -> Bool)?
}

struct HomeTimelinePresentationModifier: ViewModifier {
    let timelineStore: NostrHomeTimelineStore
    let bindings: HomeTimelinePresentationBindings
    let actions: HomeTimelinePresentationActions
    @ObservedObject var sessionStore: NostrSessionStore

    private var hasLiveAccount: Bool {
        sessionStore.account != nil
    }

    private var accountID: String? {
        sessionStore.account?.pubkey
    }

    private var eventStore: NostrEventStore? {
        hasLiveAccount ? timelineStore.relayStatusEventStore : nil
    }

    private var accountSummaries: [NostrAccountSummary] {
        _ = timelineStore.resolvedContentRevision
        return sessionStore.accountSummaries(
            eventStore: timelineStore.relayStatusEventStore
        )
    }

    private var relayURLs: [String] {
        hasLiveAccount ? timelineStore.resolvedRelays : []
    }

    private var relayRuntimeStates: [String: NostrRelayConnectionState] {
        hasLiveAccount ? timelineStore.relayRuntimeStates : [:]
    }

    private var isComposeSubmitAvailable: Bool {
        !hasLiveAccount || sessionStore.signer != nil
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: bindings.isComposerPresented) {
                composerSheet
            }
            .sheet(isPresented: bindings.isSettingsPresented) {
                settingsSheet
            }
            .sheet(isPresented: bindings.isFiltersSettingsPresented) {
                filtersSheet
            }
            .sheet(isPresented: bindings.isRelayStatusPresented) {
                relayStatusSheet
            }
            .fullScreenCover(isPresented: isFullscreenMediaPresented) {
                fullscreenMediaViewer
            }
            .sheet(item: bindings.browserDestination) { destination in
                TimelineInAppBrowserView(url: destination.url)
                    .ignoresSafeArea()
            }
    }

    private var composerSheet: some View {
        ComposeSheetView(
            mode: bindings.composeSheetMode.wrappedValue,
            isSubmitAvailable: isComposeSubmitAvailable,
            onSubmit: actions.onComposeSubmit,
            accountID: accountID,
            eventStore: eventStore
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
    }

    private var settingsSheet: some View {
        SettingsView(
            onClose: dismissSettings,
            swipeSettings: bindings.swipeSettings,
            accountID: accountID,
            eventStore: eventStore,
            accountSummaries: accountSummaries,
            onSelectAccount: actions.onSelectAccount,
            onRemoveAccount: actions.onRemoveAccount,
            onAddAccount: actions.onAddAccount
        )
        .presentationCornerRadius(26)
    }

    private var filtersSheet: some View {
        NavigationStack {
            NostrListSettingsView(
                accountID: accountID,
                eventStore: eventStore
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismissFiltersSettings)
                }
            }
        }
        .presentationCornerRadius(26)
    }

    private var relayStatusSheet: some View {
        RelayStatusSheetView(
            relayURLs: relayURLs,
            relayRuntimeStates: relayRuntimeStates,
            accountID: accountID,
            eventStore: eventStore,
            syncPolicy: timelineStore.currentSyncPolicy
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(26)
    }

    @ViewBuilder
    private var fullscreenMediaViewer: some View {
        if let request = bindings.fullscreenMedia.wrappedValue {
            TimelineFullscreenMediaViewer(
                media: request.media,
                initialTileIndex: request.initialTileIndex,
                onClose: dismissFullscreenMedia
            )
        }
    }

    private var isFullscreenMediaPresented: Binding<Bool> {
        Binding(
            get: { bindings.fullscreenMedia.wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    dismissFullscreenMedia()
                }
            }
        )
    }

    private func dismissSettings() {
        bindings.isSettingsPresented.wrappedValue = false
    }

    private func dismissFiltersSettings() {
        bindings.isFiltersSettingsPresented.wrappedValue = false
    }

    private func dismissFullscreenMedia() {
        bindings.fullscreenMedia.wrappedValue = nil
    }
}

extension View {
    func homeTimelinePresentations(
        timelineStore: NostrHomeTimelineStore,
        sessionStore: NostrSessionStore,
        bindings: HomeTimelinePresentationBindings,
        actions: HomeTimelinePresentationActions
    ) -> some View {
        modifier(
            HomeTimelinePresentationModifier(
                timelineStore: timelineStore,
                bindings: bindings,
                actions: actions,
                sessionStore: sessionStore
            )
        )
    }
}
