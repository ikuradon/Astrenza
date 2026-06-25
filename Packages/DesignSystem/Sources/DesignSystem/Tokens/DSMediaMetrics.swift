public struct DSMediaMetrics: Equatable, Codable, Sendable {
    public var gridDivider: Double
    public var cornerRadius: Double
    public var minimumReservedHeight: Double
    public var maximumHomeHeight: Double
    public var defaultAspectRatio: Double
    public var linkPreviewImageAspectRatio: Double

    public init(
        gridDivider: Double,
        cornerRadius: Double,
        minimumReservedHeight: Double,
        maximumHomeHeight: Double,
        defaultAspectRatio: Double,
        linkPreviewImageAspectRatio: Double
    ) {
        self.gridDivider = gridDivider
        self.cornerRadius = cornerRadius
        self.minimumReservedHeight = minimumReservedHeight
        self.maximumHomeHeight = maximumHomeHeight
        self.defaultAspectRatio = defaultAspectRatio
        self.linkPreviewImageAspectRatio = linkPreviewImageAspectRatio
    }

    public static let timeline = DSMediaMetrics(
        gridDivider: DSSpacing.hairline.value,
        cornerRadius: DSRadius.card.value,
        minimumReservedHeight: 120,
        maximumHomeHeight: 320,
        defaultAspectRatio: 16.0 / 9.0,
        linkPreviewImageAspectRatio: 16.0 / 9.0
    )
}
