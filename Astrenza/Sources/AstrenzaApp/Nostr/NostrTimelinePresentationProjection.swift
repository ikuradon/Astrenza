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

    static func linkSummary(
        from linkURLs: [URL],
        media: TimelineMedia? = nil
    ) -> TimelineLinkSummary? {
        let summarizedURLs: ArraySlice<URL>
        switch media {
        case .linkPreview, .unresolvedLink:
            summarizedURLs = linkURLs.dropFirst()
        case .gallery, nil:
            summarizedURLs = linkURLs[...]
        }

        guard !summarizedURLs.isEmpty else { return nil }
        let hosts = Array(Set(summarizedURLs.compactMap(\.host))).sorted()
        return TimelineLinkSummary(
            totalCount: summarizedURLs.count,
            visibleHosts: hosts,
            unresolvedCount: summarizedURLs.count
        )
    }
}
