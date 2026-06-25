import Foundation
import Testing
@testable import DesignSystem

@Suite("Timeline row layout contract")
struct TimelineRowLayoutContractTests {
    @Test("Home contract represents delayed resolve layout constraints")
    func homeContractRepresentsDelayedResolveConstraints() {
        let contract = TimelineRowLayoutContract(
            rowKind: .home,
            canChangeHeightAfterFirstDisplay: false,
            reservedMediaAspectRatio: 16.0 / 9.0,
            reservedMediaHeight: 180,
            linkPreviewMode: .fixedCompactCard,
            quoteMode: .collapsedCard,
            replyHeaderMode: .oneLine,
            bodyMentionRendering: .resolvedDisplayNameWithFallback,
            maxBodyLinesInCollapsedMode: 8,
            maxQuoteLines: 3,
            allowsInlineParentPreviewInHome: false
        )

        #expect(!contract.canChangeHeightAfterFirstDisplay)
        #expect(contract.reservedMediaAspectRatio == 16.0 / 9.0)
        #expect(contract.reservedMediaHeight == 180)
        #expect(contract.linkPreviewMode == .fixedCompactCard)
        #expect(contract.quoteMode == .collapsedCard)
        #expect(contract.replyHeaderMode == .oneLine)
        #expect(contract.bodyMentionRendering == .resolvedDisplayNameWithFallback)
        #expect(contract.maxBodyLinesInCollapsedMode == 8)
        #expect(contract.maxQuoteLines == 3)
        #expect(!contract.allowsInlineParentPreviewInHome)
    }

    @Test("Layout contract is codable for projection and fixture storage")
    func layoutContractIsCodable() throws {
        let contract = TimelineRowLayoutContract.homeTextOnly

        let data = try JSONEncoder().encode(contract)
        let decoded = try JSONDecoder().decode(TimelineRowLayoutContract.self, from: data)

        #expect(decoded == contract)
    }
}
