public struct DSLinkPreviewMetrics: Equatable, Codable, Sendable {
    public var imageAspectRatio: Double
    public var imageMaxHeight: Double
    public var textAreaMinHeight: Double
    public var textAreaMaxHeight: Double
    public var totalMaxHeight: Double

    public init(
        imageAspectRatio: Double,
        imageMaxHeight: Double,
        textAreaMinHeight: Double,
        textAreaMaxHeight: Double,
        totalMaxHeight: Double
    ) {
        self.imageAspectRatio = imageAspectRatio
        self.imageMaxHeight = imageMaxHeight
        self.textAreaMinHeight = textAreaMinHeight
        self.textAreaMaxHeight = textAreaMaxHeight
        self.totalMaxHeight = totalMaxHeight
    }

    public var compactImageHeight: Double {
        min(textAreaMinHeight, imageMaxHeight)
    }

    public var compactImageWidth: Double {
        compactImageHeight * imageAspectRatio
    }
}

public struct DSMediaMetrics: Equatable, Codable, Sendable {
    public var gridDivider: Double
    public var cornerRadius: Double
    public var minimumReservedHeight: Double
    public var maximumHomeHeight: Double
    public var defaultAspectRatio: Double
    public var linkPreview: DSLinkPreviewMetrics

    public var linkPreviewImageAspectRatio: Double {
        get { linkPreview.imageAspectRatio }
        set { linkPreview.imageAspectRatio = newValue }
    }

    public init(
        gridDivider: Double,
        cornerRadius: Double,
        minimumReservedHeight: Double,
        maximumHomeHeight: Double,
        defaultAspectRatio: Double,
        linkPreviewImageAspectRatio: Double,
        linkPreviewImageMaxHeight: Double = 180,
        linkPreviewTextAreaMinHeight: Double = 92,
        linkPreviewTextAreaMaxHeight: Double = 118,
        linkPreviewTotalMaxHeight: Double = 306
    ) {
        self.gridDivider = gridDivider
        self.cornerRadius = cornerRadius
        self.minimumReservedHeight = minimumReservedHeight
        self.maximumHomeHeight = maximumHomeHeight
        self.defaultAspectRatio = defaultAspectRatio
        self.linkPreview = DSLinkPreviewMetrics(
            imageAspectRatio: linkPreviewImageAspectRatio,
            imageMaxHeight: linkPreviewImageMaxHeight,
            textAreaMinHeight: linkPreviewTextAreaMinHeight,
            textAreaMaxHeight: linkPreviewTextAreaMaxHeight,
            totalMaxHeight: linkPreviewTotalMaxHeight
        )
    }

    public static let timeline = DSMediaMetrics(
        gridDivider: DSSpacing.hairline.value,
        cornerRadius: DSRadius.card.value,
        minimumReservedHeight: 120,
        maximumHomeHeight: 320,
        defaultAspectRatio: 16.0 / 9.0,
        linkPreviewImageAspectRatio: 1.91,
        linkPreviewImageMaxHeight: 180,
        linkPreviewTextAreaMinHeight: 92,
        linkPreviewTextAreaMaxHeight: 118,
        linkPreviewTotalMaxHeight: 306
    )
}
