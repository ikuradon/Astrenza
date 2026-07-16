import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline presentation state")
@MainActor
struct HomeTimelinePresentationStateTests {
    @Test("Default state has no active presentation")
    func defaultStateIsIdle() {
        let state = HomeTimelinePresentationState()

        #expect(!state.isComposerPresented)
        #expect(!state.isSettingsPresented)
        #expect(!state.isFiltersSettingsPresented)
        #expect(!state.isRelayStatusPresented)
        #expect(state.composeSheetMode == .post)
        #expect(state.fullscreenMedia == nil)
        #expect(state.browserDestination == nil)
    }

    @Test(
        "Composer rejects lifecycle and sheet blockers",
        arguments: ComposerBlocker.allCases
    )
    func composerRejectsRequiredBlockers(_ blocker: ComposerBlocker) {
        var state = HomeTimelinePresentationState()
        let isInitialPresentationReady = blocker.configure(&state)

        let accepted = state.prepareComposer(
            mode: .reply,
            isInitialPresentationReady: isInitialPresentationReady
        )

        #expect(!accepted)
        #expect(state.composeSheetMode == .post)
    }

    @Test("Composer keeps preparation separate from next-loop activation")
    func composerUsesTwoPhaseActivation() throws {
        var state = HomeTimelinePresentationState()
        state.isRelayStatusPresented = true
        state.presentBrowser(
            url: try #require(URL(string: "https://example.com/thread"))
        )
        state.presentFullscreenMedia(.gallery([]), initialTileIndex: 3)

        let accepted = state.prepareComposer(
            mode: .reply,
            isInitialPresentationReady: true
        )

        #expect(accepted)
        #expect(state.composeSheetMode == .reply)
        #expect(!state.isComposerPresented)

        state.activatePreparedComposer()

        #expect(state.isComposerPresented)
        #expect(state.isRelayStatusPresented)
        #expect(state.browserDestination != nil)
        #expect(state.fullscreenMedia != nil)
    }

    @Test(
        "Auxiliary sheets reject every other active presentation",
        arguments: AuxiliarySheet.allCases
    )
    func auxiliarySheetsAreMutuallyExclusive(
        _ requestedSheet: AuxiliarySheet
    ) throws {
        var allowedState = HomeTimelinePresentationState()

        #expect(request(requestedSheet, on: &allowedState))
        #expect(isPresented(requestedSheet, in: allowedState))
        #expect(request(requestedSheet, on: &allowedState))

        for blocker in PresentationBlocker.allCases
        where blocker != requestedSheet.correspondingBlocker {
            var blockedState = HomeTimelinePresentationState()
            try blocker.activate(on: &blockedState)

            #expect(!request(requestedSheet, on: &blockedState))
            #expect(!isPresented(requestedSheet, in: blockedState))
        }
    }

    @Test("Payload presentation and explicit dismissal remain independent")
    func payloadsAndDismissalsStayScoped() throws {
        var state = HomeTimelinePresentationState()
        let url = try #require(URL(string: "https://example.com/note"))

        let didRequestSettings = state.requestSettings()
        #expect(didRequestSettings)
        state.presentFullscreenMedia(.gallery([]), initialTileIndex: 2)
        state.presentBrowser(url: url)

        #expect(state.fullscreenMedia?.initialTileIndex == 2)
        #expect(state.browserDestination?.url == url)

        state.dismissSettings()
        state.dismissFullscreenMedia()

        #expect(!state.isSettingsPresented)
        #expect(state.fullscreenMedia == nil)
        #expect(state.browserDestination?.url == url)

        state.isFiltersSettingsPresented = true
        state.dismissFiltersSettings()

        #expect(!state.isFiltersSettingsPresented)
    }

    private func request(
        _ sheet: AuxiliarySheet,
        on state: inout HomeTimelinePresentationState
    ) -> Bool {
        switch sheet {
        case .settings:
            state.requestSettings()
        case .filters:
            state.requestFiltersSettings()
        case .relayStatus:
            state.requestRelayStatus()
        }
    }

    private func isPresented(
        _ sheet: AuxiliarySheet,
        in state: HomeTimelinePresentationState
    ) -> Bool {
        switch sheet {
        case .settings:
            state.isSettingsPresented
        case .filters:
            state.isFiltersSettingsPresented
        case .relayStatus:
            state.isRelayStatusPresented
        }
    }
}

enum ComposerBlocker: CaseIterable, Sendable {
    case initialPresentation
    case composer
    case settings
    case filters

    func configure(
        _ state: inout HomeTimelinePresentationState
    ) -> Bool {
        switch self {
        case .initialPresentation:
            return false
        case .composer:
            state.isComposerPresented = true
            return true
        case .settings:
            state.isSettingsPresented = true
            return true
        case .filters:
            state.isFiltersSettingsPresented = true
            return true
        }
    }
}

enum AuxiliarySheet: CaseIterable, Sendable {
    case settings
    case filters
    case relayStatus

    var correspondingBlocker: PresentationBlocker {
        switch self {
        case .settings:
            .settings
        case .filters:
            .filters
        case .relayStatus:
            .relayStatus
        }
    }
}

enum PresentationBlocker: CaseIterable, Equatable, Sendable {
    case composer
    case settings
    case filters
    case relayStatus
    case browser
    case fullscreenMedia

    @MainActor
    func activate(
        on state: inout HomeTimelinePresentationState
    ) throws {
        switch self {
        case .composer:
            state.isComposerPresented = true
        case .settings:
            state.isSettingsPresented = true
        case .filters:
            state.isFiltersSettingsPresented = true
        case .relayStatus:
            state.isRelayStatusPresented = true
        case .browser:
            state.presentBrowser(
                url: try #require(URL(string: "https://example.com"))
            )
        case .fullscreenMedia:
            state.presentFullscreenMedia(.gallery([]), initialTileIndex: 0)
        }
    }
}
