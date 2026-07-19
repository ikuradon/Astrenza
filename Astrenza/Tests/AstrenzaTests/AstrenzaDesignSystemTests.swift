import Foundation
import Testing

@Suite("Astrenza Design System source policy")
struct AstrenzaDesignSystemTests {
    @Test("Shared visual values are defined only by the Design System")
    func sharedVisualValuesAreCentralized() throws {
        let rules = [
            SourceRule(
                label: "custom color",
                pattern: #"\bColor\s*\(\s*(?:red|white)\s*:"#
            ),
            SourceRule(
                label: "fixed SwiftUI font size",
                pattern: #"\.font\s*\(\s*\.system\s*\(\s*size:\s*[0-9]"#
            ),
            SourceRule(
                label: "fixed UIKit font size",
                pattern: #"UIFont(?:\.systemFont\s*\(\s*ofSize:|\s*\([^\n]*size:)\s*[0-9]"#
            ),
            SourceRule(
                label: "shared stack spacing",
                pattern: #"spacing:\s*(?:1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|18|20|22|24|26|28|30|32|34)(?=\D|$)"#
            ),
            SourceRule(
                label: "shared padding",
                pattern: #"\.padding\(\s*(?:(?:\.[A-Za-z]+)\s*,\s*)?(?:1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|18|20|22|24|26|28|30|32|34)\s*\)"#
            ),
            SourceRule(
                label: "shared corner radius",
                pattern: #"(?:cornerRadius:\s*|\.cornerRadius\(\s*)(?:8|9|10|12|13|14|15|16|18|20|24|26)(?=\D|$)"#
            ),
            SourceRule(
                label: "shared spacer length",
                pattern: #"Spacer\(\s*minLength:\s*(?:1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|18|20|22|24|26|28|30|32|34)\s*\)"#
            ),
            SourceRule(
                label: "shared motion duration",
                pattern: #"duration:\s*(?:0\.12|0\.16|0\.18|0\.2|0\.20|0\.22|0\.24|0\.28|0\.3|0\.30)(?=\D|$)"#
            ),
        ]

        let violations = try productionSourceFiles().flatMap { sourceURL in
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            return rules.compactMap { rule -> String? in
                guard rule.matches(source) else { return nil }
                return "\(sourceURL.lastPathComponent): \(rule.label)"
            }
        }

        #expect(
            violations.isEmpty,
            "共有デザイン値はAstrenzaDesignSystem.swiftへ移動してください: \(violations.joined(separator: ", "))"
        )
    }

    private func productionSourceFiles() throws -> [URL] {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let appRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/AstrenzaApp", directoryHint: .isDirectory)
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: appRoot,
                includingPropertiesForKeys: resourceKeys
            )
        )

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "swift",
                  url.lastPathComponent != "AstrenzaDesignSystem.swift" else {
                return nil
            }
            return url
        }
    }
}

private struct SourceRule {
    let label: String
    let expression: NSRegularExpression

    init(label: String, pattern: String) {
        self.label = label
        expression = try! NSRegularExpression(pattern: pattern)
    }

    func matches(_ source: String) -> Bool {
        expression.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) != nil
    }
}
