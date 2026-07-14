import Testing
@testable import Astrenza

@Suite("Home timeline relay runtime terminator")
struct HomeTimelineRelayRuntimeTerminatorTests {
    @Test("Terminations are serialized and only the latest completion runs")
    @MainActor
    func serializesTerminationsAndSelectsLatestCompletion() async throws {
        let terminator = HomeTimelineRelayRuntimeTerminator()
        let gate = RelayRuntimeTerminationGate()
        let recorder = RelayRuntimeTerminationRecorder()

        terminator.schedule(
            termination: {
                await recorder.append("first-start")
                await gate.wait()
                await recorder.append("first-end")
            },
            onLatestCompletion: {
                await recorder.append("first-completion")
            }
        )
        try #require(await waitUntil {
            await recorder.values() == ["first-start"]
        })

        terminator.schedule(
            termination: {
                await recorder.append("second-start")
                await recorder.append("second-end")
            },
            onLatestCompletion: {
                await recorder.append("second-completion")
            }
        )
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(terminator.isTerminating)
        #expect(await recorder.values() == ["first-start"])

        await gate.open()
        try #require(await waitUntil { !terminator.isTerminating })
        let values = await recorder.values()

        #expect(values == [
            "first-start",
            "first-end",
            "second-start",
            "second-end",
            "second-completion"
        ])
    }

    @Test("Latest completion observes an idle reusable terminator")
    @MainActor
    func completionObservesIdleReusableTerminator() async throws {
        let terminator = HomeTimelineRelayRuntimeTerminator()
        let probe = RelayRuntimeTerminationCompletionProbe()

        terminator.schedule(
            termination: {},
            onLatestCompletion: {
                probe.isTerminatingValues.append(terminator.isTerminating)
            }
        )
        try #require(await waitUntil {
            probe.isTerminatingValues.count == 1
        })

        terminator.schedule(
            termination: {},
            onLatestCompletion: {
                probe.isTerminatingValues.append(terminator.isTerminating)
            }
        )
        try #require(await waitUntil {
            probe.isTerminatingValues.count == 2
        })

        #expect(probe.isTerminatingValues == [false, false])
        #expect(!terminator.isTerminating)
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
private final class RelayRuntimeTerminationCompletionProbe {
    var isTerminatingValues: [Bool] = []
}

private actor RelayRuntimeTerminationRecorder {
    private var recordedValues: [String] = []

    func append(_ value: String) {
        recordedValues.append(value)
    }

    func values() -> [String] {
        recordedValues
    }
}

private actor RelayRuntimeTerminationGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
