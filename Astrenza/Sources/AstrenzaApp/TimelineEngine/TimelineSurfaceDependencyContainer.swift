import AstrenzaCore
import Foundation

protocol TimelineRepositoryStoreWindowComposing: Sendable {
    func compose(
        _ window: TimelineRepositoryInitialWindow,
        _ accountID: AccountID,
        _ timelineKey: TimelineKey,
        _ policy: TimelineVisibleWindowPolicy
    ) throws -> TimelineRepositoryStoreWindowComposition
}

struct TimelineRepositoryStoreWindowComposerDependency: TimelineRepositoryStoreWindowComposing {
    var boundary: any TimelineRepositoryBoundaryProtocol

    init(boundary: any TimelineRepositoryBoundaryProtocol = FixtureTimelineRepositoryBoundary()) {
        self.boundary = boundary
    }

    func compose(
        _ window: TimelineRepositoryInitialWindow,
        _ accountID: AccountID,
        _ timelineKey: TimelineKey,
        _ policy: TimelineVisibleWindowPolicy
    ) throws -> TimelineRepositoryStoreWindowComposition {
        try TimelineRepositoryStoreWindowComposer.compose(
            window,
            accountID: accountID,
            timelineKey: timelineKey,
            policy: policy,
            boundary: boundary
        )
    }
}

struct TimelineInitialRestoreDependencies: Sendable {
    func makePlan(
        composition: TimelineRepositoryStoreWindowComposition,
        requestedAnchorItemKey: String? = nil
    ) -> TimelineInitialRestorePlan {
        TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composition,
            requestedAnchorItemKey: requestedAnchorItemKey
        ))
    }

    func coordinatorExpectation(
        for plan: TimelineInitialRestorePlan,
        timestampMS: Int64
    ) -> TimelineInitialRestoreCoordinatorExpectation {
        TimelineInitialRestoreCoordinatorAdapter.expectation(
            for: plan,
            restoreGateTimestampMS: timestampMS
        )
    }
}

struct TimelineSurfaceSnapshotCoordinatorExpectation: Codable, Equatable, Sendable {
    var coordinatorOwnsDataSourceApply: Bool
    var allowsDirectDataSourceApply: Bool
    var allowsInitialRestoreItemRemovalOrAddition: Bool

    init(
        coordinatorOwnsDataSourceApply: Bool = true,
        allowsDirectDataSourceApply: Bool = false,
        allowsInitialRestoreItemRemovalOrAddition: Bool = false
    ) {
        self.coordinatorOwnsDataSourceApply = coordinatorOwnsDataSourceApply
        self.allowsDirectDataSourceApply = allowsDirectDataSourceApply
        self.allowsInitialRestoreItemRemovalOrAddition = allowsInitialRestoreItemRemovalOrAddition
    }
}

enum TimelineSurfaceClosedDependency: String, Codable, Equatable, Sendable {
    case absent
}

struct TimelineSurfaceRuntimeDependencies: Codable, Equatable, Sendable {
    var remoteClient: TimelineSurfaceClosedDependency
    var mediaResolver: TimelineSurfaceClosedDependency
    var linkPreviewResolver: TimelineSurfaceClosedDependency
    var targetResolver: TimelineSurfaceClosedDependency

    var isClosedAndUnused: Bool {
        remoteClient == .absent
            && mediaResolver == .absent
            && linkPreviewResolver == .absent
            && targetResolver == .absent
    }

    static let closed = TimelineSurfaceRuntimeDependencies(
        remoteClient: .absent,
        mediaResolver: .absent,
        linkPreviewResolver: .absent,
        targetResolver: .absent
    )
}

enum TimelineSurfaceDiagnosticsDestination: String, Codable, Equatable, Sendable {
    case localNoop
}

struct TimelineSurfaceDiagnosticsSink: Codable, Equatable, Sendable {
    var destination: TimelineSurfaceDiagnosticsDestination

    static let localNoop = TimelineSurfaceDiagnosticsSink(destination: .localNoop)
}

struct TimelineFixedClock: Codable, Equatable, Sendable {
    var nowMS: Int64

    func nowMilliseconds() -> Int64 {
        nowMS
    }
}

struct TimelineSurfaceDependencyContainer: Sendable {
    var mode: AstrenzaTimelineEngineMode
    var repositoryStore: any TimelineRepositoryStore
    var windowComposer: any TimelineRepositoryStoreWindowComposing
    var initialRestore: TimelineInitialRestoreDependencies
    var snapshotCoordinator: TimelineSurfaceSnapshotCoordinatorExpectation
    var diagnosticsSink: TimelineSurfaceDiagnosticsSink
    var clock: TimelineFixedClock
    var runtime: TimelineSurfaceRuntimeDependencies

    init(
        mode: AstrenzaTimelineEngineMode,
        repositoryStore: any TimelineRepositoryStore,
        windowComposer: any TimelineRepositoryStoreWindowComposing = TimelineRepositoryStoreWindowComposerDependency(),
        initialRestore: TimelineInitialRestoreDependencies = TimelineInitialRestoreDependencies(),
        snapshotCoordinator: TimelineSurfaceSnapshotCoordinatorExpectation = TimelineSurfaceSnapshotCoordinatorExpectation(),
        diagnosticsSink: TimelineSurfaceDiagnosticsSink = .localNoop,
        clock: TimelineFixedClock,
        runtime: TimelineSurfaceRuntimeDependencies = .closed
    ) {
        self.mode = mode
        self.repositoryStore = repositoryStore
        self.windowComposer = windowComposer
        self.initialRestore = initialRestore
        self.snapshotCoordinator = snapshotCoordinator
        self.diagnosticsSink = diagnosticsSink
        self.clock = clock
        self.runtime = runtime
    }

    static func offline(
        mode: AstrenzaTimelineEngineMode,
        repositoryStore: any TimelineRepositoryStore,
        windowComposer: any TimelineRepositoryStoreWindowComposing = TimelineRepositoryStoreWindowComposerDependency(),
        clock: TimelineFixedClock
    ) -> TimelineSurfaceDependencyContainer {
        TimelineSurfaceDependencyContainer(
            mode: mode,
            repositoryStore: repositoryStore,
            windowComposer: windowComposer,
            clock: clock,
            runtime: .closed
        )
    }

    func makeInitialRestorePlan(
        from composition: TimelineRepositoryStoreWindowComposition,
        requestedAnchorItemKey: String? = nil
    ) -> TimelineInitialRestorePlan {
        initialRestore.makePlan(
            composition: composition,
            requestedAnchorItemKey: requestedAnchorItemKey
        )
    }
}

struct TimelineEngineTestDependencies: Sendable {
    var container: TimelineSurfaceDependencyContainer
}
