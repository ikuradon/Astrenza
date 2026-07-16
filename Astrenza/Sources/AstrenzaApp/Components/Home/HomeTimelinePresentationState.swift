import Foundation

struct HomeTimelinePresentationState {
    var isComposerPresented = false
    var isSettingsPresented = false
    var isFiltersSettingsPresented = false
    var isRelayStatusPresented = false
    var composeSheetMode: ComposeSheetMode = .post
    var fullscreenMedia: TimelineFullscreenMediaRequest?
    var browserDestination: TimelineBrowserDestination?

    @discardableResult
    mutating func prepareComposer(
        mode: ComposeSheetMode,
        isInitialPresentationReady: Bool
    ) -> Bool {
        guard isInitialPresentationReady,
              !isComposerPresented,
              !isSettingsPresented,
              !isFiltersSettingsPresented
        else { return false }

        composeSheetMode = mode
        return true
    }

    mutating func activatePreparedComposer() {
        isComposerPresented = true
    }

    @discardableResult
    mutating func requestSettings() -> Bool {
        guard !isComposerPresented,
              !isFiltersSettingsPresented,
              !isRelayStatusPresented,
              browserDestination == nil,
              fullscreenMedia == nil
        else { return false }

        isSettingsPresented = true
        return true
    }

    @discardableResult
    mutating func requestFiltersSettings() -> Bool {
        guard !isComposerPresented,
              !isSettingsPresented,
              !isRelayStatusPresented,
              browserDestination == nil,
              fullscreenMedia == nil
        else { return false }

        isFiltersSettingsPresented = true
        return true
    }

    @discardableResult
    mutating func requestRelayStatus() -> Bool {
        guard !isComposerPresented,
              !isSettingsPresented,
              !isFiltersSettingsPresented,
              browserDestination == nil,
              fullscreenMedia == nil
        else { return false }

        isRelayStatusPresented = true
        return true
    }

    mutating func presentFullscreenMedia(
        _ media: TimelineMedia,
        initialTileIndex: Int
    ) {
        fullscreenMedia = TimelineFullscreenMediaRequest(
            media: media,
            initialTileIndex: initialTileIndex
        )
    }

    mutating func presentBrowser(url: URL) {
        browserDestination = TimelineBrowserDestination(url: url)
    }

    mutating func dismissSettings() {
        isSettingsPresented = false
    }

    mutating func dismissFiltersSettings() {
        isFiltersSettingsPresented = false
    }

    mutating func dismissFullscreenMedia() {
        fullscreenMedia = nil
    }
}
