import CoreGraphics
import UIKit
import XCTest

enum TimelineUISnapshotConfiguration {
    static let deviceName = "iPhone 17"
    static let systemVersion = "26.5"
    static let screenWidth: CGFloat = 402
    static let renderScale: CGFloat = 3
    static let perChannelTolerance: UInt8 = 3
    static let maximumDifferentPixelRatio = 0.0005
    static let minimumVisibleChangeRatio = 0.005
    static let captureIdentifier = "astrenza.debug.timeline.snapshot.capture"
    static let resolveIdentifier = "astrenza.debug.timeline.snapshot.resolve"
    static let resolvedIdentifier = "astrenza.debug.timeline.snapshot.resolved"
    static let performanceIdentifier = "astrenza.debug.timeline.performance.feed"
}

extension XCTestCase {
    @MainActor
    func launchTimelineSnapshotApp(snapshotCase: String) throws -> (XCUIApplication, XCUIElement) {
        try assertTimelineUISnapshotEnvironment()

        let application = XCUIApplication()
        application.launchArguments = [
            "-AstrenzaDebugRoute", "timeline-snapshot",
            "-AstrenzaSnapshotCase", snapshotCase
        ]
        application.launch()

        let captureElement = application
            .descendants(matching: .any)[TimelineUISnapshotConfiguration.captureIdentifier]
        XCTAssertTrue(
            captureElement.waitForExistence(timeout: 8),
            "DEBUG snapshot capture route did not become ready"
        )
        XCTAssertEqual(
            captureElement.frame.width,
            TimelineUISnapshotConfiguration.screenWidth,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(captureElement.frame.height, 1)
        return (application, captureElement)
    }

    @MainActor
    func stableTimelineScreenshot(of element: XCUIElement) async throws -> UIImage {
        var previousImage: UIImage?

        for _ in 0..<5 {
            try? await Task.sleep(for: .milliseconds(350))
            let image = try croppedTimelineScreenshot(of: element)
            if let previousImage {
                let comparison = try TimelineUISnapshotPixelComparison(
                    reference: previousImage,
                    actual: image,
                    perChannelTolerance: 0,
                    producesDifferenceImage: false
                )
                if comparison.sizeMatches, comparison.differentPixelCount == 0 {
                    return image
                }
            }
            previousImage = image
        }

        throw TimelineUISnapshotError.unstableCompositorFrames
    }

    @MainActor
    func assertTimelineUISnapshot(
        _ image: UIImage,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let sourceFileURL = URL(fileURLWithPath: String(describing: file))
        let referenceDirectory = sourceFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent("TimelineSnapshotUITests", isDirectory: true)
        let referenceURL = referenceDirectory.appendingPathComponent("\(name).png")
#if ASTRENZA_RECORD_SNAPSHOTS
        let shouldRecord = true
#else
        let shouldRecord = ProcessInfo.processInfo.environment["ASTRENZA_RECORD_SNAPSHOTS"] == "1"
#endif

        if shouldRecord {
            try FileManager.default.createDirectory(
                at: referenceDirectory,
                withIntermediateDirectories: true
            )
            guard let data = image.pngData() else {
                throw TimelineUISnapshotError.couldNotEncodePNG
            }
            try data.write(to: referenceURL, options: .atomic)
            return
        }

        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            attachTimelineSnapshot(image, name: "\(name)-actual")
            XCTFail(
                "Missing snapshot reference: \(referenceURL.path). Re-run with ASTRENZA_RECORD_SNAPSHOTS.",
                file: file,
                line: line
            )
            return
        }

        let referenceData = try Data(contentsOf: referenceURL)
        guard let referenceImage = UIImage(data: referenceData) else {
            throw TimelineUISnapshotError.couldNotDecodeReference
        }
        let comparison = try TimelineUISnapshotPixelComparison(
            reference: referenceImage,
            actual: image,
            perChannelTolerance: TimelineUISnapshotConfiguration.perChannelTolerance
        )

        guard comparison.sizeMatches else {
            attachTimelineSnapshot(referenceImage, name: "\(name)-expected")
            attachTimelineSnapshot(image, name: "\(name)-actual")
            XCTFail(
                "Snapshot size changed for \(name): expected \(comparison.referenceSize), got \(comparison.actualSize)",
                file: file,
                line: line
            )
            return
        }

        guard comparison.differentPixelRatio <= TimelineUISnapshotConfiguration.maximumDifferentPixelRatio else {
            attachTimelineSnapshot(referenceImage, name: "\(name)-expected")
            attachTimelineSnapshot(image, name: "\(name)-actual")
            if let differenceImage = comparison.differenceImage {
                attachTimelineSnapshot(differenceImage, name: "\(name)-difference")
            }
            XCTFail(
                "Snapshot mismatch for \(name): \(comparison.differentPixelCount)/\(comparison.pixelCount) pixels differ",
                file: file,
                line: line
            )
            return
        }
    }

    @MainActor
    func assertTimelineUISnapshotsVisiblyDiffer(
        _ firstImage: UIImage,
        _ secondImage: UIImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let comparison = try TimelineUISnapshotPixelComparison(
            reference: firstImage,
            actual: secondImage,
            perChannelTolerance: TimelineUISnapshotConfiguration.perChannelTolerance,
            producesDifferenceImage: false
        )
        guard comparison.sizeMatches else {
            XCTFail("Late-arrival captures must have the same size", file: file, line: line)
            return
        }
        XCTAssertGreaterThan(
            comparison.differentPixelRatio,
            TimelineUISnapshotConfiguration.minimumVisibleChangeRatio,
            "Late-arriving content did not produce a visible update",
            file: file,
            line: line
        )
    }

    @MainActor
    private func croppedTimelineScreenshot(of element: XCUIElement) throws -> UIImage {
        let screenshot = XCUIScreen.main.screenshot().image
        guard screenshot.imageOrientation == .up,
              let screenImage = screenshot.cgImage
        else {
            throw TimelineUISnapshotError.unsupportedScreenshotOrientation
        }

        let scale = CGFloat(screenImage.width) / screenshot.size.width
        guard scale == TimelineUISnapshotConfiguration.renderScale else {
            throw TimelineUISnapshotError.unexpectedRenderScale(scale)
        }

        let frame = element.frame
        let minX = floor(frame.minX * scale)
        let minY = floor(frame.minY * scale)
        let maxX = ceil(frame.maxX * scale)
        let maxY = ceil(frame.maxY * scale)
        let cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard cropRect.minX >= 0,
              cropRect.minY >= 0,
              cropRect.maxX <= CGFloat(screenImage.width),
              cropRect.maxY <= CGFloat(screenImage.height),
              let croppedImage = screenImage.cropping(to: cropRect)
        else {
            throw TimelineUISnapshotError.captureFrameOutsideScreen(frame)
        }

        return UIImage(
            cgImage: croppedImage,
            scale: TimelineUISnapshotConfiguration.renderScale,
            orientation: .up
        )
    }

    @MainActor
    private func assertTimelineUISnapshotEnvironment() throws {
#if targetEnvironment(simulator)
        let simulatorName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
        XCTAssertEqual(simulatorName, TimelineUISnapshotConfiguration.deviceName)
#else
        XCTFail("Timeline UI snapshots require an iOS Simulator")
#endif
        let systemVersion = UIDevice.current.systemVersion
        if systemVersion != TimelineUISnapshotConfiguration.systemVersion {
            XCTFail(
                "Unexpected simulator system version: expected "
                    + TimelineUISnapshotConfiguration.systemVersion
                    + ", got "
                    + systemVersion
            )
        }
    }

    private func attachTimelineSnapshot(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct TimelineUISnapshotPixelComparison {
    let referenceSize: CGSize
    let actualSize: CGSize
    let pixelCount: Int
    let differentPixelCount: Int
    let differenceImage: UIImage?

    var sizeMatches: Bool {
        referenceSize == actualSize
    }

    var differentPixelRatio: Double {
        guard pixelCount > 0 else { return sizeMatches ? 0 : 1 }
        return Double(differentPixelCount) / Double(pixelCount)
    }

    init(
        reference: UIImage,
        actual: UIImage,
        perChannelTolerance: UInt8,
        producesDifferenceImage: Bool = true
    ) throws {
        guard let referenceCGImage = reference.cgImage,
              let actualCGImage = actual.cgImage
        else {
            throw TimelineUISnapshotError.missingCGImage
        }

        referenceSize = CGSize(width: referenceCGImage.width, height: referenceCGImage.height)
        actualSize = CGSize(width: actualCGImage.width, height: actualCGImage.height)
        guard referenceCGImage.width == actualCGImage.width,
              referenceCGImage.height == actualCGImage.height
        else {
            pixelCount = 0
            differentPixelCount = 0
            differenceImage = nil
            return
        }

        let width = referenceCGImage.width
        let height = referenceCGImage.height
        let referencePixels = try Self.rgbaPixels(from: referenceCGImage)
        let actualPixels = try Self.rgbaPixels(from: actualCGImage)
        var differencePixels = producesDifferenceImage ? referencePixels : []
        var differentPixelCount = 0

        for pixelOffset in stride(from: 0, to: referencePixels.count, by: 4) {
            var maximumDelta: UInt8 = 0
            for channelOffset in 0..<4 {
                let referenceValue = referencePixels[pixelOffset + channelOffset]
                let actualValue = actualPixels[pixelOffset + channelOffset]
                let delta = referenceValue > actualValue
                    ? referenceValue - actualValue
                    : actualValue - referenceValue
                maximumDelta = max(maximumDelta, delta)
            }

            guard maximumDelta > perChannelTolerance else { continue }
            differentPixelCount += 1
            if producesDifferenceImage {
                differencePixels[pixelOffset] = 255
                differencePixels[pixelOffset + 1] = 24
                differencePixels[pixelOffset + 2] = 24
                differencePixels[pixelOffset + 3] = 255
            }
        }

        pixelCount = width * height
        self.differentPixelCount = differentPixelCount
        differenceImage = producesDifferenceImage
            ? try Self.image(from: differencePixels, width: width, height: height)
            : nil
    }

    private static func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw TimelineUISnapshotError.couldNotCreateContext
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private static func image(from pixels: [UInt8], width: Int, height: Int) throws -> UIImage {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            throw TimelineUISnapshotError.couldNotCreateDifferenceImage
        }
        return UIImage(cgImage: image, scale: TimelineUISnapshotConfiguration.renderScale, orientation: .up)
    }
}

private enum TimelineUISnapshotError: Error {
    case unstableCompositorFrames
    case couldNotEncodePNG
    case couldNotDecodeReference
    case unsupportedScreenshotOrientation
    case unexpectedRenderScale(CGFloat)
    case captureFrameOutsideScreen(CGRect)
    case missingCGImage
    case couldNotCreateContext
    case couldNotCreateDifferenceImage
}
