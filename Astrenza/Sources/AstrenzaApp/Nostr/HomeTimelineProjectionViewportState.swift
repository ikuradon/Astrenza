enum HomeTimelineProjectionViewportTransition: Equatable, Sendable {
    case setRestoreAnchor(String?)
    case setNewestWindow(Bool)
    case restoreViewport(anchorEventID: String?)
    case resetToNewest
}

struct HomeTimelineProjectionViewportState: Equatable, Sendable {
    private(set) var restoreAnchorEventID: String?
    private(set) var isAtNewestWindow: Bool

    init(
        restoreAnchorEventID: String? = nil,
        isAtNewestWindow: Bool = true
    ) {
        self.restoreAnchorEventID = restoreAnchorEventID
        self.isAtNewestWindow = isAtNewestWindow
    }

    func applying(
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> HomeTimelineProjectionViewportState? {
        var next = self
        switch transition {
        case .setRestoreAnchor(let anchorEventID):
            next.restoreAnchorEventID = anchorEventID
            if anchorEventID != nil {
                next.isAtNewestWindow = false
            }
        case .setNewestWindow(let isAtNewestWindow):
            guard !isAtNewestWindow || restoreAnchorEventID == nil else {
                return nil
            }
            next.isAtNewestWindow = isAtNewestWindow
        case .restoreViewport(let anchorEventID):
            next.restoreAnchorEventID = anchorEventID
            next.isAtNewestWindow = false
        case .resetToNewest:
            next.restoreAnchorEventID = nil
            next.isAtNewestWindow = true
        }
        return next == self ? nil : next
    }
}

@MainActor
final class HomeProjectionViewportCoordinator {
    private var state: HomeTimelineProjectionViewportState

    init(
        initialState: HomeTimelineProjectionViewportState =
            HomeTimelineProjectionViewportState()
    ) {
        state = initialState
    }

    var restoreAnchorEventID: String? {
        state.restoreAnchorEventID
    }

    var isAtNewestWindow: Bool {
        state.isAtNewestWindow
    }

    @discardableResult
    func apply(
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Bool {
        guard let next = state.applying(transition) else { return false }
        state = next
        return true
    }
}
