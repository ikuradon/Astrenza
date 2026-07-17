import NostrProtocol

public protocol NostrEventReading: Sendable {
    func event(id: String) throws -> NostrEvent?
    func events(ids: [String], now: Int) throws -> [NostrEvent]
}

public protocol NostrEventWriting: Sendable {
    func save(events: [NostrEvent], receivedAt: Int) throws
}
