import SwiftUI

@main
struct AstrenzaApp: App {
    private let launchMode = AstrenzaLaunchMode()

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let debugRoute = launchMode.debugRoute {
                AstrenzaDebugLaunchView(route: debugRoute)
            } else {
                AstrenzaRootView()
            }
#else
            AstrenzaRootView()
#endif
        }
    }
}
