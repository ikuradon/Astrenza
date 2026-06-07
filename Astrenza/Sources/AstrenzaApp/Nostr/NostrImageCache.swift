import Foundation
import AstrenzaCore
import UIKit

final class NostrImageCache: @unchecked Sendable {
    static let shared = NostrImageCache()

    private let dataCache: NostrRemoteDataCache
    private let imageCache = NSCache<NSURL, UIImage>()

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
        let cacheKey = url as NSURL
        if let image = imageCache.object(forKey: cacheKey) {
            return image
        }

        guard let data = cachedImageData(for: url),
              let image = UIImage(data: data)
        else { return nil }
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    func memoryCachedImage(for url: URL) -> UIImage? {
        imageCache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async throws -> UIImage {
        if let cachedImage = memoryCachedImage(for: url) {
            return cachedImage
        }

        let data: Data
        if let cachedData = cachedImageData(for: url) {
            data = cachedData
        } else {
            data = try await dataCache.data(for: url)
        }

        guard let image = await Self.decodedImage(from: data) else {
            throw NostrImageCacheError.invalidImageData
        }
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    func store(data: Data, response: URLResponse, for request: URLRequest) {
        dataCache.store(data: data, response: response, for: request)
    }

    func request(for url: URL, cachePolicy: URLRequest.CachePolicy) -> URLRequest {
        dataCache.request(for: url, cachePolicy: cachePolicy)
    }

    private static func decodedImage(from data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) {
            UIImage(data: data)
        }.value
    }
}

enum NostrImageCacheError: Error, Equatable {
    case invalidImageData
}
