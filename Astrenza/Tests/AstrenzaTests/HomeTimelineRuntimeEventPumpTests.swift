import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime event pump")
struct HomeTimelineRuntimeEventPumpTests {
    @Test("Event bursts flush at the bound and before EOSE in packet order")
    @MainActor
    func boundedEventBatchesPreserveEOSEOrder() async throws {
        let source = RuntimePacketStreamStub()
        let probe = RuntimePacketBatchProbe()
        let pump = HomeTimelineRuntimeEventPump(policy: .init(
            maxEventCount: 2,
            maxDelayNanoseconds: 1_000_000_000
        ))
        _ = pump.start(
            stream: { await source.stream() },
            isSourceCurrent: { true },
            onPacket: { packets in
                probe.batches.append(packets)
            }
        )
        try #require(await pump.waitUntilReady())
        let first = runtimeEventPacket(idCharacter: "1")
        let second = runtimeEventPacket(idCharacter: "2")
        let third = runtimeEventPacket(idCharacter: "3")
        let eose = NostrRelayRuntimePacket.eose(
            relayURL: "wss://relay.example",
            subscriptionID: "astrenza-home-forward"
        )

        await source.emit(first)
        await source.emit(second)
        try #require(await waitUntil { probe.batches.count == 1 })
        await source.emit(third)
        await source.emit(eose)
        try #require(await waitUntil { probe.batches.count == 3 })

        #expect(probe.batches == [[first, second], [third], [eose]])
        pump.cancel()
    }

    @Test("One stream becomes ready, forwards packets, and clears state when it ends")
    @MainActor
    func streamLifecycle() async throws {
        let source = RuntimePacketStreamStub()
        let probe = RuntimePacketProbe()
        let pump = HomeTimelineRuntimeEventPump()

        let didStart = pump.start(
            stream: { await source.stream() },
            isSourceCurrent: { true },
            onPacket: { packets in
                probe.packets.append(contentsOf: packets)
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
            onPacket: { packets in
                probe.packets.append(contentsOf: packets)
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
            onPacket: { packets in
                probe.packets.append(contentsOf: packets)
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

    private func runtimeEventPacket(idCharacter: String) -> NostrRelayRuntimePacket {
        .event(
            relayURL: "wss://relay.example",
            subscriptionID: "astrenza-home-forward",
            event: NostrEvent(
                id: String(repeating: idCharacter, count: 64),
                pubkey: String(repeating: "a", count: 64),
                createdAt: 100,
                kind: 1,
                tags: [],
                content: idCharacter,
                sig: String(repeating: "b", count: 128)
            )
        )
    }
}

@MainActor
private final class RuntimePacketProbe {
    var packets: [NostrRelayRuntimePacket] = []
}

@MainActor
private final class RuntimePacketBatchProbe {
    var batches: [[NostrRelayRuntimePacket]] = []
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
