import Foundation

struct TimelineHomeCollectionViewOffscreenHarnessResultReader: Codable, Equatable, Sendable {
    var result: TimelineHomeOffscreenConstructionHarnessResult

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeCollectionViewOffscreenHarnessResultReader {
        TimelineHomeCollectionViewOffscreenHarnessResultReader(
            result: try decoder.decode(
                TimelineHomeOffscreenConstructionHarnessResult.self,
                from: data
            )
        )
    }

    var consumer: TimelineHomeOffscreenConstructionHarnessResultConsumer {
        TimelineHomeOffscreenConstructionHarnessResultConsumer(result: result)
    }
}

struct TimelineHomeOffscreenConstructionHarnessResultConsumer: Codable, Equatable, Sendable {
    var result: TimelineHomeOffscreenConstructionHarnessResult

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeOffscreenConstructionHarnessResultConsumer {
        try TimelineHomeCollectionViewOffscreenHarnessResultReader
            .decodeFixtureJSON(data, decoder: decoder)
            .consumer
    }

    var isAllowed: Bool {
        result.offscreenConstructionAllowed
    }

    var rejectionIssueKinds: [TimelineHomeOffscreenConstructionRejection] {
        result.rejectionReasons
    }

    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind {
        result.constructionKind
    }

    var noWindowAttached: Bool {
        result.controllerLoadedOffscreen && !result.isAttachedToWindow
    }

    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision {
        result.renderedRouteAfterConstruction
    }

    var routeActivationAllowed: Bool {
        result.routeActivationAllowed
    }

    var collectionViewRouteConstructedFromRoot: Bool {
        result.collectionViewRouteConstructedFromRoot
    }

    var timelineSurfaceConstructedFromRoot: Bool {
        result.timelineSurfaceConstructedFromRoot
    }

    var timelineCollectionViewControllerConstructedFromRoot: Bool {
        result.timelineCollectionViewControllerConstructedFromRoot
    }

    var coordinatorOwnedDataSourceApplyAllowed: Bool {
        result.coordinatorOwnedDataSourceApplyAllowed
    }

    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool {
        result.forbiddenDataSourceApplyOutsideCoordinatorCalled
    }

    var networkStarted: Bool {
        result.networkStarted
    }

    var dbWriteAttempted: Bool {
        result.dbWriteAttempted
    }

    var readMarkerAdvanced: Bool {
        result.readMarkerAdvanced
    }

    var controllerItemIDs: [String] {
        result.controllerItemIDs
    }

    var diagnosticsArtifactSummary: TimelineHomeRootRouteArtifactSnapshot {
        result.diagnosticsArtifactSummary
    }

    var artifactDeterministicSummary: String {
        diagnosticsArtifactSummary.deterministicSummary
    }

    var debugSummary: TimelineHomeOffscreenConstructionDebugSummary {
        TimelineHomeOffscreenConstructionDebugSummary.make(from: self)
    }

    var deterministicDebugSummary: String {
        debugSummary.deterministicText
    }
}

struct TimelineHomeOffscreenConstructionHarnessResult: Codable, Equatable, Sendable {
    var offscreenConstructionAllowed: Bool
    var rejectionReasons: [TimelineHomeOffscreenConstructionRejection]
    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind
    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision
    var routeActivationAllowed: Bool
    var collectionViewRouteConstructedFromRoot: Bool
    var timelineSurfaceConstructedFromRoot: Bool
    var timelineCollectionViewControllerConstructedFromRoot: Bool
    var controllerLoadedOffscreen: Bool
    var isAttachedToWindow: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool
    var controllerItemIDs: [String]
    var diagnosticsArtifactSummary: TimelineHomeRootRouteArtifactSnapshot

    init(
        offscreenConstructionAllowed: Bool,
        rejectionReasons: [TimelineHomeOffscreenConstructionRejection],
        constructionKind: TimelineHomeCollectionViewRouteConstructionKind,
        renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision,
        routeActivationAllowed: Bool,
        collectionViewRouteConstructedFromRoot: Bool,
        timelineSurfaceConstructedFromRoot: Bool,
        timelineCollectionViewControllerConstructedFromRoot: Bool,
        controllerLoadedOffscreen: Bool,
        isAttachedToWindow: Bool,
        networkStarted: Bool,
        dbWriteAttempted: Bool,
        readMarkerAdvanced: Bool,
        coordinatorOwnedDataSourceApplyAllowed: Bool,
        forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool,
        controllerItemIDs: [String],
        diagnosticsArtifactSummary: TimelineHomeRootRouteArtifactSnapshot = .unavailable
    ) {
        self.offscreenConstructionAllowed = offscreenConstructionAllowed
        self.rejectionReasons = rejectionReasons
        self.constructionKind = constructionKind
        self.renderedRouteAfterConstruction = renderedRouteAfterConstruction
        self.routeActivationAllowed = routeActivationAllowed
        self.collectionViewRouteConstructedFromRoot = collectionViewRouteConstructedFromRoot
        self.timelineSurfaceConstructedFromRoot = timelineSurfaceConstructedFromRoot
        self.timelineCollectionViewControllerConstructedFromRoot = timelineCollectionViewControllerConstructedFromRoot
        self.controllerLoadedOffscreen = controllerLoadedOffscreen
        self.isAttachedToWindow = isAttachedToWindow
        self.networkStarted = networkStarted
        self.dbWriteAttempted = dbWriteAttempted
        self.readMarkerAdvanced = readMarkerAdvanced
        self.coordinatorOwnedDataSourceApplyAllowed = coordinatorOwnedDataSourceApplyAllowed
        self.forbiddenDataSourceApplyOutsideCoordinatorCalled = forbiddenDataSourceApplyOutsideCoordinatorCalled
        self.controllerItemIDs = controllerItemIDs
        self.diagnosticsArtifactSummary = diagnosticsArtifactSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offscreenConstructionAllowed = try container.decode(Bool.self, forKey: .offscreenConstructionAllowed)
        rejectionReasons = try container.decode(
            [TimelineHomeOffscreenConstructionRejection].self,
            forKey: .rejectionReasons
        )
        constructionKind = try container.decode(
            TimelineHomeCollectionViewRouteConstructionKind.self,
            forKey: .constructionKind
        )
        renderedRouteAfterConstruction = try container.decode(
            TimelineHomeRootVisibleRouteDecision.self,
            forKey: .renderedRouteAfterConstruction
        )
        routeActivationAllowed = try container.decode(Bool.self, forKey: .routeActivationAllowed)
        collectionViewRouteConstructedFromRoot = try container.decode(
            Bool.self,
            forKey: .collectionViewRouteConstructedFromRoot
        )
        timelineSurfaceConstructedFromRoot = try container.decode(
            Bool.self,
            forKey: .timelineSurfaceConstructedFromRoot
        )
        timelineCollectionViewControllerConstructedFromRoot = try container.decode(
            Bool.self,
            forKey: .timelineCollectionViewControllerConstructedFromRoot
        )
        controllerLoadedOffscreen = try container.decode(Bool.self, forKey: .controllerLoadedOffscreen)
        isAttachedToWindow = try container.decode(Bool.self, forKey: .isAttachedToWindow)
        networkStarted = try container.decode(Bool.self, forKey: .networkStarted)
        dbWriteAttempted = try container.decode(Bool.self, forKey: .dbWriteAttempted)
        readMarkerAdvanced = try container.decode(Bool.self, forKey: .readMarkerAdvanced)
        coordinatorOwnedDataSourceApplyAllowed = try container.decode(
            Bool.self,
            forKey: .coordinatorOwnedDataSourceApplyAllowed
        )
        forbiddenDataSourceApplyOutsideCoordinatorCalled = try container.decode(
            Bool.self,
            forKey: .forbiddenDataSourceApplyOutsideCoordinatorCalled
        )
        controllerItemIDs = try container.decode([String].self, forKey: .controllerItemIDs)
        diagnosticsArtifactSummary = try container.decodeIfPresent(
            TimelineHomeRootRouteArtifactSnapshot.self,
            forKey: .diagnosticsArtifactSummary
        ) ?? .unavailable
    }

    var deterministicDebugSummary: String {
        TimelineHomeOffscreenConstructionDebugSummary
            .make(from: TimelineHomeOffscreenConstructionHarnessResultConsumer(result: self))
            .deterministicText
    }
}

enum TimelineHomeOffscreenConstructionRejection: String, Codable, Equatable, Sendable {
    case readinessBlocked
    case unsupportedConstructionKind
    case renderedRouteNotLegacy
    case routeActivationOpen
    case rootRouteConstructionOpen
    case rootSurfaceConstructionOpen
    case rootControllerConstructionOpen
    case sideEffectFlagsDirty
    case constructionPlanClosed
}

struct TimelineHomeOffscreenConstructionDebugSummary: Codable, Equatable, Sendable {
    var isAllowed: Bool
    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind
    var noWindowAttached: Bool
    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision
    var routeActivationAllowed: Bool
    var collectionViewRouteConstructedFromRoot: Bool
    var timelineSurfaceConstructedFromRoot: Bool
    var timelineCollectionViewControllerConstructedFromRoot: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var controllerLoadedOffscreen: Bool
    var isAttachedToWindow: Bool
    var controllerItemIDs: [String]
    var rejectionIssueKinds: [TimelineHomeOffscreenConstructionRejection]
    var diagnosticsArtifactSummary: TimelineHomeRootRouteArtifactSnapshot

    static func make(
        from consumer: TimelineHomeOffscreenConstructionHarnessResultConsumer
    ) -> TimelineHomeOffscreenConstructionDebugSummary {
        TimelineHomeOffscreenConstructionDebugSummary(
            isAllowed: consumer.isAllowed,
            constructionKind: consumer.constructionKind,
            noWindowAttached: consumer.noWindowAttached,
            renderedRouteAfterConstruction: consumer.renderedRouteAfterConstruction,
            routeActivationAllowed: consumer.routeActivationAllowed,
            collectionViewRouteConstructedFromRoot: consumer.collectionViewRouteConstructedFromRoot,
            timelineSurfaceConstructedFromRoot: consumer.timelineSurfaceConstructedFromRoot,
            timelineCollectionViewControllerConstructedFromRoot: consumer.timelineCollectionViewControllerConstructedFromRoot,
            networkStarted: consumer.networkStarted,
            dbWriteAttempted: consumer.dbWriteAttempted,
            readMarkerAdvanced: consumer.readMarkerAdvanced,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: consumer.forbiddenDataSourceApplyOutsideCoordinatorCalled,
            coordinatorOwnedDataSourceApplyAllowed: consumer.coordinatorOwnedDataSourceApplyAllowed,
            controllerLoadedOffscreen: consumer.result.controllerLoadedOffscreen,
            isAttachedToWindow: consumer.result.isAttachedToWindow,
            controllerItemIDs: consumer.controllerItemIDs,
            rejectionIssueKinds: consumer.rejectionIssueKinds,
            diagnosticsArtifactSummary: consumer.diagnosticsArtifactSummary
        )
    }

    var deterministicText: String {
        [
            "allowed=\(isAllowed)",
            "kind=\(constructionKind.rawValue)",
            "noWindow=\(noWindowAttached)",
            "rendered=\(renderedRouteAfterConstruction.rawValue)",
            "activation=\(routeActivationAllowed)",
            "rootFlags(route=\(collectionViewRouteConstructedFromRoot),surface=\(timelineSurfaceConstructedFromRoot),controller=\(timelineCollectionViewControllerConstructedFromRoot))",
            "sideEffects(network=\(networkStarted),dbWrite=\(dbWriteAttempted),readMarker=\(readMarkerAdvanced),forbiddenDataSourceApply=\(forbiddenDataSourceApplyOutsideCoordinatorCalled))",
            "coordinatorApplyAllowed=\(coordinatorOwnedDataSourceApplyAllowed)",
            "offscreen(viewLoaded=\(controllerLoadedOffscreen),attachedToWindow=\(isAttachedToWindow),itemIDs=\(controllerItemIDs.debugList))",
            "rejections=\(rejectionIssueKinds.map(\.rawValue).debugList)",
            "artifactSummary={\(diagnosticsArtifactSummary.deterministicSummary)}"
        ].joined(separator: " ")
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
