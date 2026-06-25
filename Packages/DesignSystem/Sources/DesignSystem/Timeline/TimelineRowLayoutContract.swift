public enum TimelineRowKind: String, CaseIterable, Codable, Sendable {
    case home
    case detail
    case thread
    case profile
    case notification
    case skeleton
}

public enum LinkPreviewMode: String, CaseIterable, Codable, Sendable {
    case absent
    case urlOnly
    case fixedSkeleton
    case fixedCompactCard
    case expandedInDetail
}

public enum QuoteCardMode: String, CaseIterable, Codable, Sendable {
    case absent
    case skeleton
    case collapsedCard
    case expandedInDetail
}

public enum ReplyHeaderMode: String, CaseIterable, Codable, Sendable {
    case absent
    case oneLine
    case inlineParentInDetail
}

public enum MentionRenderingMode: String, CaseIterable, Codable, Sendable {
    case rawNpub
    case compactAtPrefix
    case resolvedDisplayNameWithFallback
}

public struct TimelineRowLayoutContract: Equatable, Codable, Sendable {
    public var rowKind: TimelineRowKind
    public var canChangeHeightAfterFirstDisplay: Bool
    public var reservedMediaAspectRatio: Double?
    public var reservedMediaHeight: Double?
    public var linkPreviewMode: LinkPreviewMode
    public var quoteMode: QuoteCardMode
    public var replyHeaderMode: ReplyHeaderMode
    public var bodyMentionRendering: MentionRenderingMode
    public var maxBodyLinesInCollapsedMode: Int?
    public var maxQuoteLines: Int
    public var allowsInlineParentPreviewInHome: Bool

    public init(
        rowKind: TimelineRowKind,
        canChangeHeightAfterFirstDisplay: Bool,
        reservedMediaAspectRatio: Double?,
        reservedMediaHeight: Double?,
        linkPreviewMode: LinkPreviewMode,
        quoteMode: QuoteCardMode,
        replyHeaderMode: ReplyHeaderMode,
        bodyMentionRendering: MentionRenderingMode,
        maxBodyLinesInCollapsedMode: Int?,
        maxQuoteLines: Int,
        allowsInlineParentPreviewInHome: Bool
    ) {
        self.rowKind = rowKind
        self.canChangeHeightAfterFirstDisplay = canChangeHeightAfterFirstDisplay
        self.reservedMediaAspectRatio = reservedMediaAspectRatio
        self.reservedMediaHeight = reservedMediaHeight
        self.linkPreviewMode = linkPreviewMode
        self.quoteMode = quoteMode
        self.replyHeaderMode = replyHeaderMode
        self.bodyMentionRendering = bodyMentionRendering
        self.maxBodyLinesInCollapsedMode = maxBodyLinesInCollapsedMode
        self.maxQuoteLines = maxQuoteLines
        self.allowsInlineParentPreviewInHome = allowsInlineParentPreviewInHome
    }

    public static let homeTextOnly = TimelineRowLayoutContract(
        rowKind: .home,
        canChangeHeightAfterFirstDisplay: false,
        reservedMediaAspectRatio: nil,
        reservedMediaHeight: nil,
        linkPreviewMode: .absent,
        quoteMode: .absent,
        replyHeaderMode: .absent,
        bodyMentionRendering: .resolvedDisplayNameWithFallback,
        maxBodyLinesInCollapsedMode: 8,
        maxQuoteLines: 3,
        allowsInlineParentPreviewInHome: false
    )

    public static func homeWithReservedMedia(aspectRatio: Double, height: Double) -> TimelineRowLayoutContract {
        TimelineRowLayoutContract(
            rowKind: .home,
            canChangeHeightAfterFirstDisplay: false,
            reservedMediaAspectRatio: aspectRatio,
            reservedMediaHeight: height,
            linkPreviewMode: .absent,
            quoteMode: .absent,
            replyHeaderMode: .absent,
            bodyMentionRendering: .resolvedDisplayNameWithFallback,
            maxBodyLinesInCollapsedMode: 8,
            maxQuoteLines: 3,
            allowsInlineParentPreviewInHome: false
        )
    }
}
