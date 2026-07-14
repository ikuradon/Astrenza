import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline link preview coordinator")
struct HomeTimelineLinkPreviewCoordinatorTests {
    @Test("Automatic resolution drains bounded batches without duplicate tasks")
    @MainActor
    func automaticResolutionDrainsBatches() async throws {
        let eventStore = try NostrEventStore.inMemory()
        for index in 0..<3 {
            try eventStore.saveLinkPreview(unresolvedPreview(index: index))
        }
        let requests = LinkPreviewRequestCounter()
        let resolver = resolver(requests: requests)
        let coordinator = HomeTimelineLinkPreviewCoordinator(
            eventStore: eventStore,
            resolver: resolver,
            batchLimit: 2
        )
        let callbacks = LinkPreviewCallbackCounter()

        let didStart = coordinator.schedule(
            scopeID: "account-a",
            policy: .default(networkType: .wifi),
            didUpdate: { callbacks.updates += 1 },
            didFail: { _ in callbacks.failures += 1 }
        )
        let duplicateStart = coordinator.schedule(
            scopeID: "account-a",
            policy: .default(networkType: .wifi),
            didUpdate: { callbacks.updates += 1 },
            didFail: { _ in callbacks.failures += 1 }
        )

        #expect(didStart)
        #expect(!duplicateStart)
        try await waitUntil {
            !coordinator.hasActiveResolution &&
                ((try? eventStore.unresolvedLinkPreviews(limit: 10)) ?? []).isEmpty
        }

        #expect(await requests.value == 3)
        #expect(callbacks.updates == 2)
        #expect(callbacks.failures == 0)
        #expect(coordinator.inFlightCount == 0)
        let urls = (0..<3).compactMap { URL(string: "https://example.test/story/\($0)") }
        let resolved = try eventStore.linkPreviews(urls: urls)
        #expect(resolved.values.allSatisfy { $0.status == "resolved" })
    }

    @Test("Tap-required policy leaves queued previews untouched")
    @MainActor
    func tapRequiredPolicyDoesNotResolve() async throws {
        let eventStore = try NostrEventStore.inMemory()
        try eventStore.saveLinkPreview(unresolvedPreview(index: 0))
        let requests = LinkPreviewRequestCounter()
        let coordinator = HomeTimelineLinkPreviewCoordinator(
            eventStore: eventStore,
            resolver: resolver(requests: requests)
        )

        let didStart = coordinator.schedule(
            scopeID: "account-a",
            policy: .default(networkType: .cellular),
            didUpdate: {},
            didFail: { _ in }
        )

        #expect(!didStart)
        #expect(!coordinator.hasActiveResolution)
        #expect(coordinator.inFlightCount == 0)
        #expect(await requests.value == 0)
        #expect(try eventStore.unresolvedLinkPreviews(limit: 10).count == 1)
    }

    @Test("Reset prevents a late HTTP result from crossing account scope")
    @MainActor
    func resetRejectsLateResolution() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let preview = unresolvedPreview(index: 0)
        try eventStore.saveLinkPreview(preview)
        let requests = LinkPreviewRequestCounter()
        let html = try #require("<html><title>Late</title></html>".data(using: .utf8))
        let resolver = NostrLinkPreviewResolver(dataLoader: { request in
            await requests.increment()
            try await Task.sleep(nanoseconds: 200_000_000)
            return (html, URLResponse(
                url: try #require(request.url),
                mimeType: "text/html",
                expectedContentLength: html.count,
                textEncodingName: "utf-8"
            ))
        })
        let coordinator = HomeTimelineLinkPreviewCoordinator(
            eventStore: eventStore,
            resolver: resolver
        )
        let callbacks = LinkPreviewCallbackCounter()

        let didStart = coordinator.schedule(
            scopeID: "account-a",
            policy: .default(networkType: .wifi),
            didUpdate: { callbacks.updates += 1 },
            didFail: { _ in callbacks.failures += 1 }
        )
        #expect(didStart)
        try await waitUntil { await requests.value == 1 }

        coordinator.reset()
        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(!coordinator.hasActiveResolution)
        #expect(coordinator.inFlightCount == 0)
        #expect(callbacks.updates == 0)
        #expect(callbacks.failures == 0)
        let stored = try eventStore.linkPreviews(urls: [try #require(URL(string: preview.url))])
        #expect(stored[preview.normalizedURL]?.status == "unresolved")
    }

    private func resolver(requests: LinkPreviewRequestCounter) -> NostrLinkPreviewResolver {
        let html = """
        <html><head>
        <meta property="og:title" content="Resolved">
        </head></html>
        """.data(using: .utf8)!
        return NostrLinkPreviewResolver(
            dataLoader: { request in
                await requests.increment()
                return (html, URLResponse(
                    url: request.url!,
                    mimeType: "text/html",
                    expectedContentLength: html.count,
                    textEncodingName: "utf-8"
                ))
            },
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }

    private func unresolvedPreview(index: Int) -> NostrLinkPreviewRecord {
        let url = "https://example.test/story/\(index)"
        return NostrLinkPreviewRecord(
            url: url,
            normalizedURL: url,
            status: "unresolved",
            title: nil,
            summary: nil,
            siteName: nil,
            imageURL: nil,
            fetchedAt: nil,
            expiresAt: nil,
            error: nil
        )
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw LinkPreviewCoordinatorTestError.timeout
    }
}

private actor LinkPreviewRequestCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@MainActor
private final class LinkPreviewCallbackCounter {
    var updates = 0
    var failures = 0
}

private enum LinkPreviewCoordinatorTestError: Error {
    case timeout
}
