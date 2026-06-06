import Foundation

public final class NostrRemoteDataCache: @unchecked Sendable {
    public static let shared = NostrRemoteDataCache()

    private let urlCache: URLCache
    private let session: URLSession

    public init(
        urlCache: URLCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "AstrenzaRemoteData"
        ),
        urlSessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.urlCache = urlCache
        let configuration = urlSessionConfiguration
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    public func cachedData(for url: URL) -> Data? {
        let request = request(for: url, cachePolicy: .returnCacheDataDontLoad)
        return urlCache.cachedResponse(for: request)?.data
    }

    public func data(for url: URL) async throws -> Data {
        if let cachedData = cachedData(for: url) {
            return cachedData
        }

        let request = request(for: url, cachePolicy: .returnCacheDataElseLoad)
        let (data, response) = try await session.data(for: request)
        store(data: data, response: response, for: request)
        return data
    }

    public func store(data: Data, response: URLResponse, for request: URLRequest) {
        urlCache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
    }

    public func request(for url: URL, cachePolicy: URLRequest.CachePolicy) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 20)
        request.setValue("public, max-stale=86400", forHTTPHeaderField: "Cache-Control")
        return request
    }
}
