import NostrProtocol

public protocol NostrEventSigning: Sendable {
    func sign(_ unsignedEvent: NostrUnsignedEvent) async throws -> NostrEvent
}

public protocol NostrEventValidating: Sendable {
    func isValid(_ event: NostrEvent) -> Bool
}

public enum NostrSigningError: Error, Equatable {
    case invalidPrivateKey
    case pubkeyMismatch(expected: String, actual: String)
}
