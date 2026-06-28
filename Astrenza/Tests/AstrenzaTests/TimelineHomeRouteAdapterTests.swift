import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRouteAdapter")
struct TimelineHomeRouteAdapterTests {
    @Test("default mode routes to legacy without fallback")
    func defaultModeRoutesToLegacyWithoutFallback() {
        let decision = TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: ["Astrenza"]),
            dependencies: .allAvailable
        )

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.requestedMode == .legacy)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.issues.isEmpty)
        #expect(decision.isFallback == false)
        #expect(decision.preventsDualMutation)
        #expect(decision.readMarkerChanged == false)
        #expect(decision.requiresNetworkWork == false)
        #expect(decision.requiresDBWrite == false)
    }

    @Test("explicit legacy routes to legacy")
    func explicitLegacyRoutesToLegacy() {
        let decision = TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                "Astrenza",
                "--timeline-engine=legacy"
            ]),
            dependencies: .allAvailable
        )

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.requestedMode == .legacy)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.issues.isEmpty)
        #expect(decision.isFallback == false)
    }

    @Test("collectionView flag with ready dependencies routes to collectionView")
    func collectionViewFlagWithReadyDependenciesRoutesToCollectionView() {
        let decision = TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                "Astrenza",
                "--timeline-engine=collectionView"
            ]),
            dependencies: .allAvailable
        )

        #expect(decision.selectedRoute == .collectionView)
        #expect(decision.requestedMode == .collectionView)
        #expect(decision.effectiveMode == .collectionView)
        #expect(decision.issues.isEmpty)
        #expect(decision.isFallback == false)
        #expect(decision.preventsDualMutation)
        #expect(decision.readMarkerChanged == false)
        #expect(decision.requiresNetworkWork == false)
        #expect(decision.requiresDBWrite == false)
    }

    @Test("collectionView flag with missing dependencies routes to legacy with typed issues")
    func collectionViewFlagWithMissingDependenciesRoutesToLegacyWithTypedIssues() {
        let decision = TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                "Astrenza",
                "--timeline-engine=collectionView"
            ]),
            dependencies: TimelineHomeRouteDependencyStatus(
                repositoryStoreAvailable: false,
                windowComposerAvailable: false,
                restoreUseCaseAvailable: false,
                coordinatorAdapterAvailable: false,
                collectionViewControllerAvailable: false,
                diagnosticsSinkAvailable: false,
                runtimeGuardAllowsCollectionView: true,
                rolloutAllowsCollectionView: true
            )
        )

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.requestedMode == .collectionView)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.isFallback)
        #expect(decision.issues.map(\.kind) == [
            .repositoryStoreUnavailable,
            .windowComposerUnavailable,
            .restoreUseCaseUnavailable,
            .coordinatorAdapterUnavailable,
            .collectionViewControllerUnavailable,
            .diagnosticsSinkUnavailable
        ])
    }

    @Test("unknown flag routes to legacy with parser issue")
    func unknownFlagRoutesToLegacyWithParserIssue() throws {
        let decision = TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                "Astrenza",
                "--timeline-engine=grid"
            ]),
            dependencies: .allAvailable
        )

        let issue = try #require(decision.issues.first)
        #expect(decision.selectedRoute == .legacy)
        #expect(decision.requestedMode == .unknown)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.isFallback)
        #expect(issue.kind == .unknownTimelineEngineMode)
        #expect(issue.argument == "--timeline-engine=grid")
        #expect(issue.rawValue == "grid")
    }

    @Test("runtime guard disabled routes to legacy")
    func runtimeGuardDisabledRoutesToLegacy() throws {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.runtimeGuardAllowsCollectionView = false

        let decision = TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                "Astrenza",
                "--timeline-engine=collectionView"
            ]),
            dependencies: dependencies
        )

        let issue = try #require(decision.issues.first)
        #expect(decision.selectedRoute == .legacy)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.isFallback)
        #expect(issue.kind == .runtimeGuardDisabled)
    }

    @Test("rollout blocked routes to legacy")
    func rolloutBlockedRoutesToLegacy() throws {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.rolloutAllowsCollectionView = false

        let decision = TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                "Astrenza",
                "--timeline-engine=collectionView"
            ]),
            dependencies: dependencies
        )

        let issue = try #require(decision.issues.first)
        #expect(decision.selectedRoute == .legacy)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.isFallback)
        #expect(issue.kind == .rolloutBlocked)
    }

    @Test("route decision prevents old and new dual mutation")
    func routeDecisionPreventsOldAndNewDualMutation() {
        let decision = TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                "Astrenza",
                "--timeline-engine=collectionView"
            ]),
            dependencies: .allAvailable
        )

        #expect(decision.preventsDualMutation)
        #expect(decision.readMarkerChanged == false)
        #expect(decision.requiresNetworkWork == false)
        #expect(decision.requiresDBWrite == false)
    }

    @Test("route adapter source stays pure and does not instantiate Home or controller")
    func routeAdapterSourceStaysPureAndDoesNotInstantiateHomeOrController() throws {
        let source = try sourceFile(named: "TimelineHomeRouteAdapter.swift")

        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("Nostr" + "HomeTimelineStore"))
        #expect(!source.contains("Home" + "TimelineView"))
        #expect(!source.contains("Astrenza" + "RootView"))
        #expect(!source.contains("Astrenza" + "StartupSplashView"))
        #expect(!source.contains("Timeline" + "FeedView"))
        #expect(!source.contains("Timeline" + "PostRow"))
        #expect(!source.contains("Timeline" + "Attachments"))
        #expect(!source.contains("TimelineSurface("))
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("delete" + "Items"))
        #expect(!source.contains("insert" + "Items"))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("GRDB"))
        #expect(!source.contains("exec" + "ute("))
        #expect(!source.contains("wri" + "te("))
    }

    @Test("route decision models are Codable Equatable and Sendable")
    func routeDecisionModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineHomeRouteMode.self)
        assertSendable(TimelineHomeRouteDependencyStatus.self)
        assertSendable(TimelineHomeRouteDecisionIssue.self)
        assertSendable(TimelineHomeRouteDecision.self)

        let decision = TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                "Astrenza",
                "--timeline-engine=grid"
            ]),
            dependencies: .allAvailable
        )

        let data = try JSONEncoder().encode(decision)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteDecision.self, from: data)

        #expect(decoded == decision)
    }

    private func sourceFile(named fileName: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/\(fileName)"),
            encoding: .utf8
        )
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
