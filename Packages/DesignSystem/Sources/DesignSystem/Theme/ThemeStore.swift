import Combine

@MainActor
public final class ThemeStore: ObservableObject {
    @Published public private(set) var theme: AppTheme

    public init(initialTheme: AppTheme = .system) {
        self.theme = initialTheme
    }

    public func setTheme(_ theme: AppTheme) {
        self.theme = theme
    }
}
