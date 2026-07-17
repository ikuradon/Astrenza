import Foundation

public typealias NostrHTTPDataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
