import Foundation

public enum NostrSyncMode: String, Codable, CaseIterable, Sendable {
    case energySaver
    case ownRelayList
    case fullOutbox
}

public enum NostrNetworkType: String, Codable, CaseIterable, Sendable {
    case wifi
    case cellular
    case other
    case unknown
}

public struct NostrSyncPolicy: Codable, Equatable, Sendable {
    public var mode: NostrSyncMode
    public var networkType: NostrNetworkType
    public var lowPowerMode: Bool
    public var tapToLoadMedia: Bool
    public var queueOGPPreviews: Bool
    public var disableOGPOnCellular: Bool
    public var reduceFullOutboxOnCellular: Bool

    public init(
        mode: NostrSyncMode,
        networkType: NostrNetworkType,
        lowPowerMode: Bool,
        tapToLoadMedia: Bool,
        queueOGPPreviews: Bool,
        disableOGPOnCellular: Bool,
        reduceFullOutboxOnCellular: Bool
    ) {
        self.mode = mode
        self.networkType = networkType
        self.lowPowerMode = lowPowerMode
        self.tapToLoadMedia = tapToLoadMedia
        self.queueOGPPreviews = queueOGPPreviews
        self.disableOGPOnCellular = disableOGPOnCellular
        self.reduceFullOutboxOnCellular = reduceFullOutboxOnCellular
    }

    public static func `default`(
        networkType: NostrNetworkType = .unknown,
        lowPowerMode: Bool = false
    ) -> NostrSyncPolicy {
        let constrained = lowPowerMode || networkType == .cellular
        return NostrSyncPolicy(
            mode: lowPowerMode ? .energySaver : .ownRelayList,
            networkType: networkType,
            lowPowerMode: lowPowerMode,
            tapToLoadMedia: constrained,
            queueOGPPreviews: true,
            disableOGPOnCellular: networkType == .cellular,
            reduceFullOutboxOnCellular: true
        )
    }
}
