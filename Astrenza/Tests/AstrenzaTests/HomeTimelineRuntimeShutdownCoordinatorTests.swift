import Testing
@testable import Astrenza

@Suite("Home timeline runtime shutdown coordinator")
@MainActor
struct HomeTimelineRuntimeShutdownTests {
    @Test("Termination state mirrors the serialized scheduler")
    func exposesSchedulerState() {
        let system = RuntimeShutdownTestSystem()

        #expect(!system.coordinator.isTerminating)
        system.scheduler.isTerminating = true
        #expect(system.coordinator.isTerminating)
    }

    @Test("A missing relay runtime does not schedule termination")
    func rejectsMissingRuntime() {
        let system = RuntimeShutdownTestSystem(hasRuntime: false)

        let didSchedule = system.coordinator.schedule(
            cancellationGeneration: system.lifecycle.cancel(),
            handlers: system.probe.handlers
        )

        #expect(!didSchedule)
        #expect(system.scheduler.terminations.isEmpty)
        #expect(system.scheduler.completions.isEmpty)
    }

    @Test("Termination stops profile observation before terminating the relay runtime")
    func stopsProfileObservationBeforeRuntime() async throws {
        let system = RuntimeShutdownTestSystem()
        let didSchedule = system.coordinator.schedule(
            cancellationGeneration: system.lifecycle.cancel(),
            handlers: system.probe.handlers
        )
        let termination = try #require(system.scheduler.terminations.first)

        await termination()

        #expect(didSchedule)
        #expect(system.session.stopProfileUpdateCount == 1)
        #expect(system.probe.runtimeTerminationCount == 1)
        #expect(system.probe.profileStopCountsAtTermination == [1])
    }

    @Test("Completion without a current lifecycle cannot restart runtime work")
    func rejectsCompletionWithoutLifecycle() async throws {
        let system = RuntimeShutdownTestSystem()
        system.probe.account = RuntimeShutdownTestSystem.account()
        _ = system.coordinator.schedule(
            cancellationGeneration: system.lifecycle.cancel(),
            handlers: system.probe.handlers
        )
        let completion = try #require(system.scheduler.completions.first)

        await completion()

        #expect(system.session.cancelRuntimeEventCount == 0)
        #expect(system.probe.commands.isEmpty)
    }

    @Test("A matching newer lifecycle restarts runtime work in order")
    func restartsMatchingNewLifecycle() async throws {
        let system = RuntimeShutdownTestSystem()
        let cancellationGeneration = system.lifecycle.cancel()
        let account = RuntimeShutdownTestSystem.account()
        _ = system.lifecycle.begin(accountID: account.pubkey)
        system.probe.account = account
        _ = system.coordinator.schedule(
            cancellationGeneration: cancellationGeneration,
            handlers: system.probe.handlers
        )
        let completion = try #require(system.scheduler.completions.first)

        await completion()

        #expect(system.session.cancelRuntimeEventCount == 1)
        #expect(system.probe.commands == [
            .resetRuntimeState,
            .startRuntimeSession,
            .configureRuntime(account: account, forceInstall: true)
        ])
    }

    @Test(
        "Incomplete or stale account lifecycle state cannot restart runtime work",
        arguments: RuntimeShutdownRestartRejection.allCases
    )
    func rejectsInvalidRestartState(
        _ rejection: RuntimeShutdownRestartRejection
    ) async throws {
        let system = RuntimeShutdownTestSystem()
        let currentAccount = RuntimeShutdownTestSystem.account()
        let cancellationGeneration: UInt64
        switch rejection {
        case .missingAccount:
            cancellationGeneration = system.lifecycle.cancel()
            _ = system.lifecycle.begin(accountID: currentAccount.pubkey)
        case .mismatchedAccount:
            cancellationGeneration = system.lifecycle.cancel()
            _ = system.lifecycle.begin(accountID: currentAccount.pubkey)
            system.probe.account = RuntimeShutdownTestSystem.account(
                pubkeyCharacter: "b",
                identifier: "other"
            )
        case .unchangedGeneration:
            let lifecycle = system.lifecycle.begin(accountID: currentAccount.pubkey)
            cancellationGeneration = lifecycle.generation
            system.probe.account = currentAccount
        }
        _ = system.coordinator.schedule(
            cancellationGeneration: cancellationGeneration,
            handlers: system.probe.handlers
        )
        let completion = try #require(system.scheduler.completions.first)

        await completion()

        #expect(system.session.cancelRuntimeEventCount == 0)
        #expect(system.probe.commands.isEmpty)
    }
}

enum RuntimeShutdownRestartRejection: CaseIterable, Sendable, CustomTestStringConvertible {
    case missingAccount
    case mismatchedAccount
    case unchangedGeneration

    var testDescription: String {
        switch self {
        case .missingAccount: "missing account"
        case .mismatchedAccount: "mismatched account"
        case .unchangedGeneration: "unchanged generation"
        }
    }
}
