public enum TimelineContextChipInteraction: String, Codable, Sendable {
    case noninteractive
    case interactive
}

public struct TimelineContextChipMetrics: Equatable, Codable, Sendable {
    public var interaction: TimelineContextChipInteraction
    public var visualHeight: Double
    public var avatarSize: Double
    public var iconSize: Double
    public var maxWidth: Double?
    public var hitTargetWidth: Double?
    public var hitTargetHeight: Double?

    public init(
        interaction: TimelineContextChipInteraction,
        visualHeight: Double,
        avatarSize: Double,
        iconSize: Double,
        maxWidth: Double? = nil,
        hitTargetWidth: Double? = nil,
        hitTargetHeight: Double? = nil
    ) {
        self.interaction = interaction
        self.visualHeight = visualHeight
        self.avatarSize = avatarSize
        self.iconSize = iconSize
        self.maxWidth = maxWidth

        switch interaction {
        case .noninteractive:
            self.hitTargetWidth = nil
            self.hitTargetHeight = nil
        case .interactive:
            self.hitTargetWidth = max(DSControlSize.minimumHitTarget, hitTargetWidth ?? visualHeight)
            self.hitTargetHeight = max(DSControlSize.minimumHitTarget, hitTargetHeight ?? visualHeight)
        }
    }

    public var minimumFrameHeight: Double {
        hitTargetHeight ?? visualHeight
    }

    public static let repostCompact = TimelineContextChipMetrics(
        interaction: .noninteractive,
        visualHeight: 28,
        avatarSize: 20,
        iconSize: DSIcon.repost.visualSize(for: .compactBadge)
    )

    public static let contentWarningPill = TimelineContextChipMetrics(
        interaction: .noninteractive,
        visualHeight: 28,
        avatarSize: 0,
        iconSize: DSIcon.warning.visualSize(for: .compactBadge)
    )

    public static let repostInteractive = TimelineContextChipMetrics(
        interaction: .interactive,
        visualHeight: 28,
        avatarSize: 20,
        iconSize: DSIcon.repost.visualSize(for: .compactBadge),
        hitTargetWidth: DSControlSize.minimumHitTarget,
        hitTargetHeight: DSControlSize.minimumHitTarget
    )
}
