import Foundation

/// Profileの表示状態です。通信中かどうかと、kind:0が存在するかどうかを分離します。
public enum NostrProfileResolutionState: Equatable, Hashable, Sendable {
    case unknown
    case fetching
    case resolved
    case unavailable
}

/// 永続化するのは最後の取得結果だけです。`fetching`はprocess-localな状態なので保存しません。
public enum NostrProfileFetchOutcome: String, Codable, Equatable, Sendable {
    case resolved
    case notFound = "not_found"
    case failed
}

public struct NostrProfileFetchRecord: Codable, Equatable, Sendable {
    public let pubkey: String
    public let outcome: NostrProfileFetchOutcome
    public let lastAttemptAt: Int
    public let lastSuccessAt: Int?
    public let nextRetryAt: Int?
    public let lastError: String?
    public let updatedAt: Int

    public init(
        pubkey: String,
        outcome: NostrProfileFetchOutcome,
        lastAttemptAt: Int,
        lastSuccessAt: Int? = nil,
        nextRetryAt: Int? = nil,
        lastError: String? = nil,
        updatedAt: Int
    ) {
        self.pubkey = pubkey
        self.outcome = outcome
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
        self.updatedAt = updatedAt
    }
}
