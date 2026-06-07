import AstrenzaCore
import SwiftUI

struct AstrenzaRootView: View {
    @StateObject private var sessionStore = NostrSessionStore()
    @StateObject private var homeTimelineStore: NostrHomeTimelineStore
    @AppStorage(AstrenzaThemeMode.storageKey) private var selectedThemeMode = AstrenzaThemeMode.system.rawValue
    private let launchMode = AstrenzaLaunchMode()

    init() {
        _homeTimelineStore = StateObject(wrappedValue: NostrHomeTimelineStore(
            relayRuntime: NostrRelayRuntime { _ in
                NostrURLSessionRelayTransport()
            },
            linkPreviewResolver: NostrLinkPreviewResolver()
        ))
    }

    var body: some View {
        Group {
            if launchMode.usesMockTimeline {
                HomeTimelineView()
            } else if let account = sessionStore.account {
                HomeTimelineView(
                    sessionStore: sessionStore,
                    liveTimelineStore: homeTimelineStore
                )
                .task(id: account.pubkey) {
                    homeTimelineStore.start(account: account)
                }
            } else {
                NostrLoginView(sessionStore: sessionStore)
            }
        }
        .preferredColorScheme(themeMode.preferredColorScheme)
    }

    private var themeMode: AstrenzaThemeMode {
        AstrenzaThemeMode(rawValue: selectedThemeMode) ?? .system
    }
}
