import SwiftUI

private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppTheme.system
}

public extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeEnvironmentKey.self] }
        set { self[AppThemeEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func appTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
    }
}
