import AstrenzaCore
@testable import Astrenza

@MainActor
final class RuntimeShutdownSchedulerSpy: HomeTimelineRuntimeTerminationScheduling {
    var isTerminating = false
    private(set) var terminations: [HomeTimelineRuntimeTermination] = []
    private(set) var completions: [HomeTimelineRuntimeTerminationCompletion] = []

    func schedule(
        termination: @escaping HomeTimelineRuntimeTermination,
        onLatestCompletion: @escaping HomeTimelineRuntimeTerminationCompletion
    ) {
        terminations.append(termination)
        completions.append(onLatestCompletion)
    }
}

@MainActor
final class RuntimeShutdownSessionSpy: HomeTimelineRuntimeSessionStopping {
    private(set) var cancelRuntimeEventCount = 0
    private(set) var stopProfileUpdateCount = 0

    func cancelRuntimeEvents() {
        cancelRuntimeEventCount += 1
    }

    func stopProfileUpdates() async {
        stopProfileUpdateCount += 1
    }
}

@MainActor
final class RuntimeShutdownHandlerProbe {
    var account: NostrAccount?
    private(set) var commands: [HomeTimelineRuntimeShutdownCommand] = []
    private(set) var runtimeTerminationCount = 0
    private(set) var profileStopCountsAtTermination: [Int] = []

    func recordRuntimeTermination(profileStopCount: Int) {
        runtimeTerminationCount += 1
        profileStopCountsAtTermination.append(profileStopCount)
    }

    var handlers: HomeTimelineRuntimeShutdownHandlers {
        HomeTimelineRuntimeShutdownHandlers(
            currentAccount: { [weak self] in self?.account },
            perform: { [weak self] command in
                self?.commands.append(command)
            }
        )
    }
}

@MainActor
struct RuntimeShutdownTestSystem {
    let scheduler: RuntimeShutdownSchedulerSpy
    let session: RuntimeShutdownSessionSpy
    let lifecycle: HomeTimelineLifecycleCoordinator
    let probe: RuntimeShutdownHandlerProbe
    let coordinator: HomeTimelineRuntimeShutdownCoordinator

    init(hasRuntime: Bool = true) {
        let scheduler = RuntimeShutdownSchedulerSpy()
        let session = RuntimeShutdownSessionSpy()
        let lifecycle = HomeTimelineLifecycleCoordinator()
        let probe = RuntimeShutdownHandlerProbe()
        let terminateRuntime: HomeTimelineRuntimeShutdownCoordinator.RuntimeTermination?
        if hasRuntime {
            terminateRuntime = { [session, probe] in
                probe.recordRuntimeTermination(
                    profileStopCount: session.stopProfileUpdateCount
                )
            }
        } else {
            terminateRuntime = nil
        }

        self.scheduler = scheduler
        self.session = session
        self.lifecycle = lifecycle
        self.probe = probe
        self.coordinator = HomeTimelineRuntimeShutdownCoordinator(
            scheduler: scheduler,
            runtimeSession: session,
            lifecycleCoordinator: lifecycle,
            terminateRuntime: terminateRuntime
        )
    }

    static func account(
        pubkeyCharacter: Character = "a",
        identifier: String = "account"
    ) -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: String(pubkeyCharacter), count: 64),
            displayIdentifier: identifier,
            readOnly: true
        )
    }
}
