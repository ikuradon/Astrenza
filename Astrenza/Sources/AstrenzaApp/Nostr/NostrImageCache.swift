import AstrenzaCore
import Foundation
import ImageIO
import UIKit

final class NostrImageCache: @unchecked Sendable {
    static let shared = NostrImageCache(dataCache: NostrRemoteDataCache())

    static let mediaMaximumPixelSize = 2_048
    static let mediaAspectRatioMaximumPixelSize = 96
    static let linkPreviewMaximumPixelSize = 1_024
    static let customEmojiMaximumPixelSize = 96

    private let dataCache: NostrRemoteDataCache
    private let pipeline: NostrImagePipeline
    private let aspectRatioCache = NSCache<NSURL, NSNumber>()

    init(
        dataCache: NostrRemoteDataCache = NostrRemoteDataCache(),
        dataProvider: (@Sendable (URL) async throws -> Data)? = nil
    ) {
        self.dataCache = dataCache
        self.pipeline = NostrImagePipeline(
            dataCache: dataCache,
            dataProvider: dataProvider ?? { url in
                try await dataCache.data(for: url)
            }
        )
    }

    convenience init(
        urlCache: URLCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "AstrenzaRemoteImages"
        ),
        urlSessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.init(
            dataCache: NostrRemoteDataCache(
                urlCache: urlCache,
                urlSessionConfiguration: urlSessionConfiguration
            )
        )
    }

    func cachedImageData(for url: URL) -> Data? {
        dataCache.cachedData(for: url)
    }

    func image(for url: URL, maximumPixelSize: Int) async throws -> UIImage {
        let image = try await pipeline.image(for: url, maximumPixelSize: maximumPixelSize)
        if image.value.size.width > 0, image.value.size.height > 0 {
            aspectRatioCache.setObject(
                NSNumber(
                    value: image.value.size.width / image.value.size.height
                ),
                forKey: url as NSURL
            )
        }
        return image.value
    }

    func cachedAspectRatio(for url: URL) -> CGFloat? {
        guard let value = aspectRatioCache.object(
            forKey: url as NSURL
        )?.doubleValue,
              value.isFinite,
              value > 0
        else { return nil }
        return CGFloat(value)
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

private struct NostrImageRequestKey: Hashable, Sendable {
    let url: URL
    let maximumPixelSize: Int
}

private struct NostrSendableImage: @unchecked Sendable {
    let value: UIImage
}

private actor NostrImagePipeline {
    private static let maximumDecodedPixelSize = NostrImageCache.mediaMaximumPixelSize

    private let dataCache: NostrRemoteDataCache
    private let dataProvider: @Sendable (URL) async throws -> Data
    private let imageCache = NSCache<NSString, UIImage>()
    private var dataTasks: [URL: Task<Data, Error>] = [:]
    private var imageTasks: [NostrImageRequestKey: Task<NostrSendableImage, Error>] = [:]

    init(
        dataCache: NostrRemoteDataCache,
        dataProvider: @escaping @Sendable (URL) async throws -> Data
    ) {
        self.dataCache = dataCache
        self.dataProvider = dataProvider
        imageCache.countLimit = 512
        imageCache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL, maximumPixelSize: Int) async throws -> NostrSendableImage {
        let requestKey = NostrImageRequestKey(
            url: url,
            maximumPixelSize: Self.normalizedPixelSize(maximumPixelSize)
        )
        let cacheKey = Self.cacheKey(for: requestKey)

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return NostrSendableImage(value: cachedImage)
        }
        if let existingTask = imageTasks[requestKey] {
            return try await existingTask.value
        }

        let dataTask = dataTask(for: url)
        let imageTask = Task.detached(priority: .userInitiated) {
            let data = try await dataTask.value
            guard let image = NostrImageDecoder.downsampledImage(
                from: data,
                maximumPixelSize: requestKey.maximumPixelSize
            ) else {
                throw NostrImageCacheError.invalidImageData
            }
            return NostrSendableImage(value: image)
        }
        imageTasks[requestKey] = imageTask

        do {
            let image = try await imageTask.value
            imageTasks.removeValue(forKey: requestKey)
            dataTasks.removeValue(forKey: url)
            imageCache.setObject(
                image.value,
                forKey: cacheKey,
                cost: Self.memoryCost(of: image.value)
            )
            return image
        } catch {
            imageTasks.removeValue(forKey: requestKey)
            dataTasks.removeValue(forKey: url)
            throw error
        }
    }

    private func dataTask(for url: URL) -> Task<Data, Error> {
        if let existingTask = dataTasks[url] {
            return existingTask
        }

        if let cachedData = dataCache.cachedData(for: url) {
            let task: Task<Data, Error> = Task.detached(priority: .userInitiated) { cachedData }
            dataTasks[url] = task
            return task
        }

        let dataProvider = dataProvider
        let task = Task.detached(priority: .userInitiated) {
            try await dataProvider(url)
        }
        dataTasks[url] = task
        return task
    }

    private static func normalizedPixelSize(_ value: Int) -> Int {
        min(max(value, 1), maximumDecodedPixelSize)
    }

    private static func cacheKey(for request: NostrImageRequestKey) -> NSString {
        "\(request.url.absoluteString)|\(request.maximumPixelSize)" as NSString
    }

    private static func memoryCost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

private enum NostrImageDecoder {
    static func downsampledImage(from data: Data, maximumPixelSize: Int) -> UIImage? {
        autoreleasepool {
            let sourceOptions = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                return nil
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ] as CFDictionary
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
                return nil
            }

            return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        }
    }
}
