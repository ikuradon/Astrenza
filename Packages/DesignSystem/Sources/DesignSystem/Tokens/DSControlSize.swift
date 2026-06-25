public struct DSControlSize: Equatable, Codable, Sendable {
    public static let minimumHitTarget: Double = 44

    public var visualSize: Double
    public var hitTargetWidth: Double
    public var hitTargetHeight: Double

    public init(visualSize: Double, hitTargetWidth: Double, hitTargetHeight: Double) {
        self.visualSize = visualSize
        self.hitTargetWidth = max(Self.minimumHitTarget, hitTargetWidth)
        self.hitTargetHeight = max(Self.minimumHitTarget, hitTargetHeight)
    }

    public static let timelineAction = DSControlSize(
        visualSize: DSIcon.reply.visualSize(for: .timelineAction),
        hitTargetWidth: minimumHitTarget,
        hitTargetHeight: minimumHitTarget
    )

    public static let composeFAB = DSControlSize(
        visualSize: DSIcon.compose.visualSize(for: .composeFAB),
        hitTargetWidth: 56,
        hitTargetHeight: 56
    )
}
