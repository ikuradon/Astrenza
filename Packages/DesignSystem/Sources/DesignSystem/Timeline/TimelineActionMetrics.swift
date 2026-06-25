public struct TimelineActionMetrics: Equatable, Codable, Sendable {
    public static let minimumHitTarget = DSControlSize.minimumHitTarget
    public static let `default` = TimelineActionMetrics()

    public var visualIconSize: Double
    public var targetWidth: Double
    public var targetHeight: Double
    public var slotCount: Int

    public init(
        visualIconSize: Double = DSControlSize.timelineAction.visualSize,
        targetWidth: Double = DSControlSize.timelineAction.hitTargetWidth,
        targetHeight: Double = DSControlSize.timelineAction.hitTargetHeight,
        slotCount: Int = 5
    ) {
        self.visualIconSize = visualIconSize
        self.targetWidth = max(Self.minimumHitTarget, targetWidth)
        self.targetHeight = max(Self.minimumHitTarget, targetHeight)
        self.slotCount = max(1, slotCount)
    }

    public func targetWidth(forContentWidth contentWidth: Double) -> Double {
        max(Self.minimumHitTarget, contentWidth / Double(slotCount))
    }
}
