import Foundation

struct TimelineHomeRootBodyActivationWiringGateReader: Codable, Equatable, Sendable {
    var result: TimelineHomeRootBodyActivationWiringResult

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRootBodyActivationWiringGateReader {
        TimelineHomeRootBodyActivationWiringGateReader(
            result: try decoder.decode(
                TimelineHomeRootBodyActivationWiringResult.self,
                from: data
            )
        )
    }

    var consumer: TimelineHomeRootBodyActivationWiringGateConsumer {
        TimelineHomeRootBodyActivationWiringGateConsumer(result: result)
    }
}

struct TimelineHomeRootBodyActivationWiringGateConsumer: Codable, Equatable, Sendable {
    var result: TimelineHomeRootBodyActivationWiringResult

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRootBodyActivationWiringGateConsumer {
        try TimelineHomeRootBodyActivationWiringGateReader
            .decodeFixtureJSON(data, decoder: decoder)
            .consumer
    }

    var wiringGateEvaluated: Bool {
        result.wiringGateEvaluated
    }

    var wiringAllowed: Bool {
        result.wiringAllowed
    }

    var renderedRouteDecision: TimelineHomeRootVisibleRouteDecision {
        result.renderedRouteDecision
    }

    var productionRootBodyChanged: Bool {
        result.productionRootBodyChanged
    }

    var legacyHomeRenderingPreserved: Bool {
        result.legacyHomeRenderingPreserved
    }

    var collectionViewRenderingActivated: Bool {
        result.collectionViewRenderingActivated
    }

    var sameSessionDoubleMutationPrevented: Bool {
        result.sameSessionDoubleMutationPrevented
    }

    var rollbackRoute: TimelineHomeRootVisibleRouteDecision {
        result.rollbackRoute
    }

    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision {
        result.manualFallbackRoute
    }

    var activationPerformed: Bool {
        result.activationPerformed
    }

    var productionRenderSwitchPerformed: Bool {
        result.productionRenderSwitchPerformed
    }

    var dataSourceApplyFromRootCalled: Bool {
        result.dataSourceApplyFromRootCalled
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

    var extraNostrHomeTimelineStoreConstructed: Bool {
        result.extraNostrHomeTimelineStoreConstructed
    }

    var issueKinds: [TimelineHomeRootBodyActivationWiringIssueKind] {
        result.issueKinds
    }

    var artifactSummary: TimelineHomeRootBodyActivationWiringArtifactSummary {
        result.artifactSummary
    }

    var debugSummary: TimelineHomeRootBodyActivationWiringDebugSummary {
        TimelineHomeRootBodyActivationWiringDebugSummary.make(from: self)
    }

    var deterministicDebugSummary: String {
        debugSummary.deterministicText
    }
}

struct TimelineHomeRootBodyActivationWiringDebugSummary: Codable, Equatable, Sendable {
    var wiringGateEvaluated: Bool
    var wiringAllowed: Bool
    var renderedRouteDecision: TimelineHomeRootVisibleRouteDecision
    var productionRootBodyChanged: Bool
    var legacyHomeRenderingPreserved: Bool
    var collectionViewRenderingActivated: Bool
    var sameSessionDoubleMutationPrevented: Bool
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var activationPerformed: Bool
    var productionRenderSwitchPerformed: Bool
    var dataSourceApplyFromRootCalled: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var issueKinds: [TimelineHomeRootBodyActivationWiringIssueKind]
    var artifactSummary: TimelineHomeRootBodyActivationWiringArtifactSummary

    static func make(
        from consumer: TimelineHomeRootBodyActivationWiringGateConsumer
    ) -> TimelineHomeRootBodyActivationWiringDebugSummary {
        TimelineHomeRootBodyActivationWiringDebugSummary(
            wiringGateEvaluated: consumer.wiringGateEvaluated,
            wiringAllowed: consumer.wiringAllowed,
            renderedRouteDecision: consumer.renderedRouteDecision,
            productionRootBodyChanged: consumer.productionRootBodyChanged,
            legacyHomeRenderingPreserved: consumer.legacyHomeRenderingPreserved,
            collectionViewRenderingActivated: consumer.collectionViewRenderingActivated,
            sameSessionDoubleMutationPrevented: consumer.sameSessionDoubleMutationPrevented,
            rollbackRoute: consumer.rollbackRoute,
            manualFallbackRoute: consumer.manualFallbackRoute,
            activationPerformed: consumer.activationPerformed,
            productionRenderSwitchPerformed: consumer.productionRenderSwitchPerformed,
            dataSourceApplyFromRootCalled: consumer.dataSourceApplyFromRootCalled,
            networkStarted: consumer.networkStarted,
            dbWriteAttempted: consumer.dbWriteAttempted,
            readMarkerAdvanced: consumer.readMarkerAdvanced,
            extraNostrHomeTimelineStoreConstructed: consumer.extraNostrHomeTimelineStoreConstructed,
            issueKinds: consumer.issueKinds,
            artifactSummary: consumer.artifactSummary
        )
    }

    var deterministicText: String {
        [
            "wiringGateEvaluated=\(wiringGateEvaluated)",
            "wiringAllowed=\(wiringAllowed)",
            "renderedRouteDecision=\(renderedRouteDecision.rawValue)",
            "productionRootBodyChanged=\(productionRootBodyChanged)",
            "legacyHomeRenderingPreserved=\(legacyHomeRenderingPreserved)",
            "collectionViewRenderingActivated=\(collectionViewRenderingActivated)",
            "sameSessionDoubleMutationPrevented=\(sameSessionDoubleMutationPrevented)",
            "rollbackRoute=\(rollbackRoute.rawValue)",
            "manualFallbackRoute=\(manualFallbackRoute.rawValue)",
            "activationPerformed=\(activationPerformed)",
            "productionRenderSwitchPerformed=\(productionRenderSwitchPerformed)",
            "sideEffects(dataSourceApplyFromRoot=\(dataSourceApplyFromRootCalled),network=\(networkStarted),dbWrite=\(dbWriteAttempted),readMarker=\(readMarkerAdvanced),extraNostrStore=\(extraNostrHomeTimelineStoreConstructed))",
            "issueKinds=\(issueKinds.map(\.rawValue).debugList)",
            "artifactSummary={\(artifactSummary.deterministicSummary)}"
        ].joined(separator: " ")
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
