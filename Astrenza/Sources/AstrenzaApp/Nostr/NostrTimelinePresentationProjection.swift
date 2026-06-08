import Foundation
import AstrenzaCore

struct NostrTimelinePresentationProjection {
    static func bodyPresentation(
        body: String,
        linkURLs: [URL],
        isFollowed: Bool,
        filterMatch: NostrFilterMatchReason? = nil
    ) -> TimelineBodyPresentation {
        if filterMatch != nil {
            return .collapsed(lineLimit: 2, reason: .filtered)
        }
        if !isFollowed && !linkURLs.isEmpty {
            return .collapsed(lineLimit: 3, reason: .lowTrustLinks)
        }
        if linkURLs.count >= 5 {
            return .collapsed(lineLimit: 4, reason: .linkHeavy)
        }
        if body.count > 1_000 {
            return .collapsed(lineLimit: 8, reason: .longText)
        }
        return .standard
    }

    static func linkSummary(from linkURLs: [URL]) -> TimelineLinkSummary? {
        guard !linkURLs.isEmpty else { return nil }
        let hosts = Array(Set(linkURLs.compactMap(\.host))).sorted()
        return TimelineLinkSummary(
            totalCount: linkURLs.count,
            visibleHosts: hosts,
            unresolvedCount: linkURLs.count
        )
    }
}
