import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeEngineMode")
struct TimelineHomeEngineModeTests {
    @Test("default mode is legacy")
    func defaultModeIsLegacy() {
        let resolution = TimelineHomeEngineModeResolver.resolve(arguments: ["Astrenza"])

        #expect(resolution.mode == .legacy)
        #expect(resolution.issues.isEmpty)
    }

    @Test("collectionView launch argument selects collectionView")
    func collectionViewLaunchArgumentSelectsCollectionView() {
        let resolution = TimelineHomeEngineModeResolver.resolve(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])

        #expect(resolution.mode == .collectionView)
        #expect(resolution.issues.isEmpty)
    }

    @Test("legacy launch argument selects legacy")
    func legacyLaunchArgumentSelectsLegacy() {
        let resolution = TimelineHomeEngineModeResolver.resolve(arguments: [
            "Astrenza",
            "--timeline-engine=legacy"
        ])

        #expect(resolution.mode == .legacy)
        #expect(resolution.issues.isEmpty)
    }

    @Test("unknown launch argument falls back to legacy with typed issue")
    func unknownLaunchArgumentFallsBackToLegacyWithTypedIssue() throws {
        let resolution = TimelineHomeEngineModeResolver.resolve(arguments: [
            "Astrenza",
            "--timeline-engine=grid"
        ])

        let issue = try #require(resolution.issues.first)
        #expect(resolution.mode == .legacy)
        #expect(resolution.issues.count == 1)
        #expect(issue.kind == .unknownTimelineEngineMode)
        #expect(issue.argument == "--timeline-engine=grid")
        #expect(issue.rawValue == "grid")
    }

    @Test("parser is pure and does not touch Home root or TimelineSurface")
    func parserIsPureAndDoesNotTouchHomeRootOrTimelineSurface() throws {
        let source = try sourceFile(named: "TimelineHomeEngineMode.swift")

        #expect(!source.contains("Astrenza" + "RootView"))
        #expect(!source.contains("Home" + "TimelineView"))
        #expect(!source.contains("Nostr" + "HomeTimelineStore"))
        #expect(!source.contains("Astrenza" + "StartupSplashView"))
        #expect(!source.contains("TimelineSurface("))
    }

    @Test("mode models are Codable Equatable and Sendable")
    func modeModelsAreCodableEquatableAndSendable() throws {
        assertSendable(AstrenzaTimelineEngineMode.self)
        assertSendable(TimelineHomeEngineModeResolution.self)
        assertSendable(TimelineHomeEngineModeIssue.self)

        let resolution = TimelineHomeEngineModeResolution(
            mode: .legacy,
            issues: [
                TimelineHomeEngineModeIssue(
                    kind: .unknownTimelineEngineMode,
                    argument: "--timeline-engine=grid",
                    rawValue: "grid"
                )
            ]
        )

        let data = try JSONEncoder().encode(resolution)
        let decoded = try JSONDecoder().decode(TimelineHomeEngineModeResolution.self, from: data)

        #expect(decoded == resolution)
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
