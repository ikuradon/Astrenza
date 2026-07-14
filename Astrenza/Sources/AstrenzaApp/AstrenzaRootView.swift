import AstrenzaCore
import SwiftUI

struct AstrenzaRootView: View {
    @StateObject private var sessionStore: NostrSessionStore
    @StateObject private var homeTimelineStore: NostrHomeTimelineStore
    @State private var isStartupSplashVisible = true
    @State private var hasPresentedStartupTimeline = false
    @State private var startupSplashStartDate = Date()
    @State private var startupSplashDismissTask: Task<Void, Never>?
    @AppStorage(AstrenzaThemeMode.storageKey) private var selectedThemeMode = AstrenzaThemeMode.system.rawValue
    private let launchMode = AstrenzaLaunchMode()
    private let startupSplashMinimumDuration: TimeInterval = 0.45

    init() {
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        _sessionStore = StateObject(
            wrappedValue: NostrSessionStore(restoreAccount: !isRunningUnitTests)
        )
        _homeTimelineStore = StateObject(wrappedValue: NostrHomeTimelineStore(
            relayRuntime: NostrRelayRuntime { _ in
                NostrURLSessionRelayTransport()
            },
            linkPreviewResolver: NostrLinkPreviewResolver(
                serviceClientProvider: {
                    let serviceConfiguration = NostrMediaResolverSettingsStore.shared.configuration()
                    guard serviceConfiguration.isUsable else { return nil }
                    return NostrMediaResolverServiceClient(configuration: serviceConfiguration)
                }
            )
        ))
    }

    var body: some View {
        ZStack {
            if launchMode.usesMockTimeline {
                HomeTimelineView(onInitialPresentationReady: markStartupTimelinePresented)
            } else if let account = sessionStore.account {
                HomeTimelineView(
                    sessionStore: sessionStore,
                    liveTimelineStore: homeTimelineStore,
                    onInitialPresentationReady: markStartupTimelinePresented
                )
                .task(id: account.pubkey) {
                    homeTimelineStore.start(account: account)
                }
            } else {
                NostrLoginView(sessionStore: sessionStore)
            }

            if shouldShowStartupSplash {
                AstrenzaStartupSplashView(
                    startDate: startupSplashStartDate,
                    status: startupStatus
                )
                    .transition(.opacity)
                    .zIndex(1_000)
            }
        }
        .preferredColorScheme(themeMode.preferredColorScheme)
        .onAppear(perform: scheduleStartupSplashDismissIfReady)
        .onChange(of: startupAccountID) { previousAccountID, currentAccountID in
            if !launchMode.usesMockTimeline,
               previousAccountID != nil,
               currentAccountID == nil {
                homeTimelineStore.cancel()
            }
            resetStartupSplash()
        }
        .onChange(of: homeTimelineStore.phase) { _, _ in
            scheduleStartupSplashDismissIfReady()
        }
        .onChange(of: homeTimelineStore.entries.count) { _, _ in
            scheduleStartupSplashDismissIfReady()
        }
    }

    private var themeMode: AstrenzaThemeMode {
        AstrenzaThemeMode(rawValue: selectedThemeMode) ?? .system
    }

    private var startupAccountID: String? {
        launchMode.usesMockTimeline ? "mock-account" : sessionStore.account?.pubkey
    }

    private var shouldShowStartupSplash: Bool {
        startupAccountID != nil && isStartupSplashVisible
    }

    private var isStartupTimelineContentReady: Bool {
        guard startupAccountID != nil else { return false }
        if launchMode.usesMockTimeline || !homeTimelineStore.entries.isEmpty {
            return true
        }

        switch homeTimelineStore.phase {
        case .loaded, .failed:
            return true
        case .idle, .resolvingRelays, .resolvingContacts, .loadingHome:
            return false
        }
    }

    private var startupStatus: NostrTimelineActivityStatus {
        if launchMode.usesMockTimeline {
            return NostrTimelineActivityStatus(
                title: "Preparing timeline",
                detail: "Loading the local preview",
                compactLabel: "Preparing"
            )
        }
        if let activityStatus = homeTimelineStore.activityStatus {
            return activityStatus
        }
        switch homeTimelineStore.phase {
        case .failed(let message):
            return NostrTimelineActivityStatus(
                title: "Home timeline unavailable",
                detail: message,
                compactLabel: "Error"
            )
        case .loaded:
            return NostrTimelineActivityStatus(
                title: "Home timeline ready",
                detail: "Restoring your last reading position",
                compactLabel: "Ready"
            )
        case .idle, .resolvingRelays, .resolvingContacts, .loadingHome:
            return NostrTimelineActivityStatus(
                title: "Preparing Home timeline",
                detail: "Checking local timeline data",
                compactLabel: "Preparing"
            )
        }
    }

    private func resetStartupSplash() {
        startupSplashDismissTask?.cancel()
        startupSplashDismissTask = nil
        startupSplashStartDate = Date()
        hasPresentedStartupTimeline = false
        isStartupSplashVisible = startupAccountID != nil
        scheduleStartupSplashDismissIfReady()
    }

    private func markStartupTimelinePresented() {
        hasPresentedStartupTimeline = true
        scheduleStartupSplashDismissIfReady()
    }

    private func scheduleStartupSplashDismissIfReady() {
        guard isStartupSplashVisible,
              hasPresentedStartupTimeline,
              isStartupTimelineContentReady
        else { return }

        startupSplashDismissTask?.cancel()
        let elapsed = Date().timeIntervalSince(startupSplashStartDate)
        let delay = max(0, startupSplashMinimumDuration - elapsed)
        startupSplashDismissTask = Task {
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    isStartupSplashVisible = false
                }
            }
        }
    }
}
