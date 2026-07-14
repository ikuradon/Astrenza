import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime event pump")
struct HomeTimelineRuntimeEventPumpTests {
    @Test("One stream becomes ready, forwards packets, and clears state when it ends")
    @MainActor
    func streamLifecycle() async throws {
        let source = RuntimePacketStreamStub()
        let probe = RuntimePacketProbe()
        let pump = HomeTimelineRuntimeEventPump()

        let didStart = pump.start(
            stream: { await source.stream() },
            isSourceCurrent: { true },
            onPacket: { packet in
                probe.packets.append(packet)
            }
        )
        let didStartDuplicate = pump.start(
            stream: { await source.stream() },
            isSourceCurrent: { true },
            onPacket: { _ in }
        )

        #expect(didStart)
        #expect(!didStartDuplicate)
        try #require(await pump.waitUntilReady())
        #expect(pump.isRunning)
        #expect(pump.isReady)
        #expect(await source.requestCount() == 1)

        let packet = NostrRelayRuntimePacket.notice(
            relayURL: "wss://relay.example",
            message: "ready"
        )
        await source.emit(packet)
        try #require(await waitUntil { probe.packets == [packet] })

        await source.finish()
        try #require(await waitUntil { !pump.isRunning })
        #expect(!pump.isReady)
        #expect(!(await pump.waitUntilReady()))
    }

    @Test("A cancelled stream cannot clobber a restarted pump")
    @MainActor
    func cancelledStreamCannotClobberRestart() async throws {
        let blockedSource = RuntimePacketStreamGate()
        let restartedSource = RuntimePacketStreamStub()
        let probe = RuntimePacketProbe()
        let pump = HomeTimelineRuntimeEventPump()

        let didStartBlockedSource = pump.start(
            stream: { await blockedSource.stream() },
            isSourceCurrent: { true },
            onPacket: { _ in }
        )
        #expect(didStartBlockedSource)
        let readinessTask = Task { @MainActor in
            await pump.waitUntilReady()
        }
        try #require(await waitUntil {
            await blockedSource.requestCount() == 1 &&
                pump.pendingReadinessWaiterCount == 1
        })

        pump.cancel()
        #expect(!(await readinessTask.value))
        #expect(!pump.isRunning)
        #expect(!pump.isReady)

        let didStartRestartedSource = pump.start(
            stream: { await restartedSource.stream() },
            isSourceCurrent: { true },
            onPacket: { packet in
                probe.packets.append(packet)
            }
        )
        #expect(didStartRestartedSource)
        try #require(await pump.waitUntilReady())
        await blockedSource.release()
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(pump.isRunning)
        #expect(pump.isReady)
        let packet = NostrRelayRuntimePacket.notice(
            relayURL: "wss://relay.example",
            message: "restarted"
        )
        await restartedSource.emit(packet)
        try #require(await waitUntil { probe.packets == [packet] })

        pump.cancel()
    }

    @Test("Packets from an invalidated source are dropped and stop the pump")
    @MainActor
    func invalidatedSourceStopsPump() async throws {
        let source = RuntimePacketStreamStub()
        let validity = RuntimeSourceValidityProbe()
        let probe = RuntimePacketProbe()
        let pump = HomeTimelineRuntimeEventPump()

        let didStart = pump.start(
            stream: { await source.stream() },
            isSourceCurrent: { validity.isCurrent },
            onPacket: { packet in
                probe.packets.append(packet)
            }
        )
        #expect(didStart)
        try #require(await pump.waitUntilReady())

        validity.isCurrent = false
        await source.emit(.notice(
            relayURL: "wss://stale.example",
            message: "stale"
        ))
        try #require(await waitUntil { !pump.isRunning })

        #expect(!pump.isReady)
        #expect(probe.packets.isEmpty)
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if await predicate() { return true }
            await Task.yield()
        }
        return false
    }
}

@MainActor
private final class RuntimePacketProbe {
    var packets: [NostrRelayRuntimePacket] = []
}

@MainActor
private final class RuntimeSourceValidityProbe {
    var isCurrent = true
}

private actor RuntimePacketStreamStub {
    private var requests = 0
    private var continuation: AsyncStream<NostrRelayRuntimePacket>.Continuation?

    func stream() -> AsyncStream<NostrRelayRuntimePacket> {
        requests += 1
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func requestCount() -> Int {
        requests
    }

    func emit(_ packet: NostrRelayRuntimePacket) {
        continuation?.yield(packet)
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}

private actor RuntimePacketStreamGate {
    private var requests = 0
    private var continuation: CheckedContinuation<AsyncStream<NostrRelayRuntimePacket>, Never>?

    func stream() async -> AsyncStream<NostrRelayRuntimePacket> {
        requests += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func requestCount() -> Int {
        requests
    }

    func release() {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: AsyncStream { streamContinuation in
            streamContinuation.finish()
        })
    }
}
