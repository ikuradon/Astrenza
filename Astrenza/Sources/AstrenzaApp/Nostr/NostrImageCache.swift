import Foundation
import AstrenzaCore
import UIKit

final class NostrImageCache: @unchecked Sendable {
    static let shared = NostrImageCache()

    private let dataCache: NostrRemoteDataCache

    init(dataCache: NostrRemoteDataCache = NostrRemoteDataCache()) {
        self.dataCache = dataCache
    }

    init(
        urlCache: URLCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "AstrenzaRemoteImages"
        ),
        urlSessionConfiguration: URLSessionConfiguration = .default
    ) {
        dataCache = NostrRemoteDataCache(urlCache: urlCache, urlSessionConfiguration: urlSessionConfiguration)
    }

    func cachedImageData(for url: URL) -> Data? {
        dataCache.cachedData(for: url)
    }

    func cachedImage(for url: URL) -> UIImage? {
        cachedImageData(for: url).flatMap(UIImage.init(data:))
    }

    func image(for url: URL) async throws -> UIImage {
        if let cachedImage = cachedImage(for: url) {
            return cachedImage
        }

        let data = try await dataCache.data(for: url)
        guard let image = UIImage(data: data) else {
            throw NostrImageCacheError.invalidImageData
        }
        return image
    }

    func store(data: Data, response: URLResponse, for request: URLRequest) {
        dataCache.store(data: data, response: response, for: request)
    }

    func request(for url: URL, cachePolicy: URLRequest.CachePolicy) -> URLRequest {
        dataCache.request(for: url, cachePolicy: cachePolicy)
    }
}

enum NostrImageCacheError: Error, Equatable {
    case invalidImageData
}
