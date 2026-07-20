import AstrenzaCore
import SwiftUI

struct HomeTimelinePresentationActions {
    let onSelectAccount: (String) -> Void
    let onRemoveAccount: (String) -> Void
    let onComposeSubmit: ComposeFeatureModel.SubmitHandler?
}

struct HomeTimelinePresentationModifier: ViewModifier {
    let timelineStore: NostrHomeTimelineStore
    let actions: HomeTimelinePresentationActions
    @ObservedObject var sessionStore: NostrSessionStore
    @Binding var presentation: HomeTimelinePresentationState
    @Binding var swipeSettings: TimelineSwipeSettings

    private var hasLiveAccount: Bool {
        sessionStore.account != nil
    }

    private var accountID: String? {
        sessionStore.account?.pubkey
    }

    private var eventStore: NostrEventStore? {
        hasLiveAccount ? timelineStore.presentationEventStore : nil
    }

    private var accountSummaries: [NostrAccountSummary] {
        sessionStore.accountSummaries(
            eventStore: timelineStore.presentationEventStore,
            metadataRevision: timelineStore.profileMetadataRevision
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
            .sheet(isPresented: $presentation.isComposerPresented) {
                composerSheet
            }
            .sheet(isPresented: $presentation.isSettingsPresented) {
                settingsSheet
            }
            .sheet(isPresented: $presentation.isFiltersSettingsPresented) {
                filtersSheet
            }
            .sheet(isPresented: $presentation.isRelayStatusPresented) {
                relayStatusSheet
            }
            .fullScreenCover(isPresented: isFullscreenMediaPresented) {
                fullscreenMediaViewer
            }
            .sheet(item: $presentation.browserDestination) { destination in
                TimelineInAppBrowserView(url: destination.url)
                    .ignoresSafeArea()
            }
    }

    private var composerSheet: some View {
        ComposeSheetView(
            context: presentation.composeContext,
            isSubmitAvailable: isComposeSubmitAvailable,
            onSubmit: actions.onComposeSubmit,
            accountID: accountID,
            eventStore: eventStore,
            accounts: accountSummaries,
            onSelectAccount: actions.onSelectAccount
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
    }

    private var settingsSheet: some View {
        SettingsView(
            onClose: dismissSettings,
            swipeSettings: $swipeSettings,
            accountID: accountID,
            eventStore: eventStore,
            sessionStore: sessionStore,
            accountSummaries: accountSummaries,
            onSelectAccount: actions.onSelectAccount,
            onRemoveAccount: actions.onRemoveAccount,
            onSyncPolicyChange: { accountID, policy in
                timelineStore.applySyncPolicy(policy, accountID: accountID)
            }
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
        if let request = presentation.fullscreenMedia {
            TimelineFullscreenMediaViewer(
                media: request.media,
                initialTileIndex: request.initialTileIndex,
                onClose: dismissFullscreenMedia
            )
        }
    }

    private var isFullscreenMediaPresented: Binding<Bool> {
        Binding(
            get: { presentation.fullscreenMedia != nil },
            set: { isPresented in
                if !isPresented {
                    dismissFullscreenMedia()
                }
            }
        )
    }

    private func dismissSettings() {
        presentation.dismissSettings()
    }

    private func dismissFiltersSettings() {
        presentation.dismissFiltersSettings()
    }

    private func dismissFullscreenMedia() {
        presentation.dismissFullscreenMedia()
    }
}

extension View {
    func homeTimelinePresentations(
        timelineStore: NostrHomeTimelineStore,
        sessionStore: NostrSessionStore,
        presentation: Binding<HomeTimelinePresentationState>,
        swipeSettings: Binding<TimelineSwipeSettings>,
        actions: HomeTimelinePresentationActions
    ) -> some View {
        modifier(
            HomeTimelinePresentationModifier(
                timelineStore: timelineStore,
                actions: actions,
                sessionStore: sessionStore,
                presentation: presentation,
                swipeSettings: swipeSettings
            )
        )
    }
}
