public struct TimelineRowMetrics: Equatable, Codable, Sendable {
    public var density: TimelineDensity
    public var horizontalPadding: Double
    public var verticalPaddingTop: Double
    public var verticalPaddingBottom: Double
    public var avatarSize: Double
    public var avatarToContentGap: Double
    public var rowContentSpacing: Double
    public var cardCornerRadius: Double
    public var mediaGridDivider: Double
    public var actionMetrics: TimelineActionMetrics

    public init(density: TimelineDensity = .comfortable) {
        self.density = density

        switch density {
        case .compact:
            self.horizontalPadding = 14
            self.verticalPaddingTop = 10
            self.verticalPaddingBottom = 8
            self.avatarSize = 40
            self.avatarToContentGap = 10
            self.rowContentSpacing = DSSpacing.sm.value
        case .comfortable:
            self.horizontalPadding = 16
            self.verticalPaddingTop = 12
            self.verticalPaddingBottom = 10
            self.avatarSize = 44
            self.avatarToContentGap = 12
            self.rowContentSpacing = DSSpacing.sm.value
        case .relaxed:
            self.horizontalPadding = 18
            self.verticalPaddingTop = 14
            self.verticalPaddingBottom = 12
            self.avatarSize = 48
            self.avatarToContentGap = 14
            self.rowContentSpacing = DSSpacing.md.value
        }

        self.cardCornerRadius = DSRadius.card.value
        self.mediaGridDivider = DSMediaMetrics.timeline.gridDivider
        self.actionMetrics = .default
    }
}
