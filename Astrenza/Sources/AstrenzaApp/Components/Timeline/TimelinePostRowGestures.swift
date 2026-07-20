import SwiftUI
import UIKit

struct TimelineRowPanGestureHost: UIViewRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.isUserInteractionEnabled = false
        view.onMovedToWindow = { markerView in
            context.coordinator.attachIfNeeded(from: markerView)
        }
        return view
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(
        _ uiView: MarkerView,
        coordinator: Coordinator
    ) {
        uiView.onMovedToWindow = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: TimelineRowPanGestureHost
        weak var markerView: MarkerView?
        private weak var scrollView: UIScrollView?
        private weak var router: TimelineRowPanGestureRouter?

        var recognizer: UIPanGestureRecognizer? {
            router?.recognizer
        }

        init(parent: TimelineRowPanGestureHost) {
            self.parent = parent
        }

        func attachIfNeeded(from markerView: MarkerView) {
            guard let targetScrollView = markerView.enclosingScrollView() else {
                detach()
                return
            }

            if scrollView !== targetScrollView || router == nil {
                detach()
                let targetRouter = TimelineRowPanGestureRouterRegistry.router(
                    for: targetScrollView
                )
                scrollView = targetScrollView
                router = targetRouter
                targetRouter.register(self)
            }
            self.markerView = markerView
        }

        func detach() {
            router?.unregister(self)
            router = nil
            scrollView = nil
            markerView = nil
        }

        func containsGestureStart(_ recognizer: UIPanGestureRecognizer) -> Bool {
            guard parent.isEnabled,
                  let markerView,
                  markerView.window != nil
            else { return false }

            return markerView.bounds.contains(recognizer.location(in: markerView))
        }

        func handleChanged(_ translationWidth: CGFloat) {
            guard parent.isEnabled else { return }
            parent.onChanged(translationWidth)
        }

        func handleEnded(_ translationWidth: CGFloat) {
            parent.onEnded(parent.isEnabled ? translationWidth : 0)
        }

        func handleCancelled() {
            parent.onEnded(0)
        }
    }

    final class MarkerView: UIView {
        var onMovedToWindow: ((MarkerView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMovedToWindow?(self)
        }
    }
}

@MainActor
final class TimelineRowGestureArbitrator {
    private(set) var suppressesRowTap = false

    func touchSequenceDidBegin() {
        suppressesRowTap = false
    }

    func horizontalSwipeDidBegin() {
        suppressesRowTap = true
    }
}

@MainActor
private final class TimelineRowPanGestureRecognizer: UIPanGestureRecognizer {
    var onTouchSequenceBegan: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouchSequenceBegan?()
        super.touchesBegan(touches, with: event)
    }
}

@MainActor
private final class TimelineRowPanGestureRouter: NSObject, UIGestureRecognizerDelegate {
    final class Registration {
        weak var participant: TimelineRowPanGestureHost.Coordinator?

        init(participant: TimelineRowPanGestureHost.Coordinator) {
            self.participant = participant
        }
    }

    weak var scrollView: UIScrollView?
    let recognizer: TimelineRowPanGestureRecognizer
    let arbitrator = TimelineRowGestureArbitrator()
    private var registrations: [Registration] = []
    private weak var activeParticipant: TimelineRowPanGestureHost.Coordinator?

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        recognizer = TimelineRowPanGestureRecognizer()
        super.init()

        recognizer.onTouchSequenceBegan = { [weak self] in
            self?.arbitrator.touchSequenceDidBegin()
        }
        recognizer.addTarget(self, action: #selector(handlePan(_:)))
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        scrollView.addGestureRecognizer(recognizer)
        scrollView.panGestureRecognizer.require(toFail: recognizer)
    }

    deinit {
        if let scrollView, recognizer.view === scrollView {
            scrollView.removeGestureRecognizer(recognizer)
        }
    }

    func register(_ participant: TimelineRowPanGestureHost.Coordinator) {
        pruneRegistrations()
        guard !registrations.contains(where: { $0.participant === participant }) else {
            return
        }
        registrations.append(Registration(participant: participant))
    }

    func unregister(_ participant: TimelineRowPanGestureHost.Coordinator) {
        if activeParticipant === participant {
            participant.handleCancelled()
            activeParticipant = nil
        }
        registrations.removeAll {
            $0.participant == nil || $0.participant === participant
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: scrollView).x

        switch recognizer.state {
        case .began:
            arbitrator.horizontalSwipeDidBegin()
            activeParticipant?.handleChanged(translation)
        case .changed:
            activeParticipant?.handleChanged(translation)
        case .ended:
            let participant = activeParticipant
            activeParticipant = nil
            participant?.handleEnded(translation)
        case .cancelled, .failed:
            let participant = activeParticipant
            activeParticipant = nil
            participant?.handleCancelled()
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        activeParticipant = nil
        guard gestureRecognizer === recognizer,
              let scrollView
        else { return false }

        let location = recognizer.location(in: scrollView)
        guard location.x > 32 else { return false }

        let velocity = recognizer.velocity(in: scrollView)
        let horizontalSpeed = abs(velocity.x)
        let verticalSpeed = abs(velocity.y)
        guard horizontalSpeed > 120,
              horizontalSpeed > verticalSpeed * 1.35
        else { return false }

        pruneRegistrations()
        activeParticipant = registrations.lazy
            .compactMap(\.participant)
            .first { $0.containsGestureStart(recognizer) }
        return activeParticipant != nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === recognizer,
              activeParticipant != nil,
              let scrollView
        else { return false }

        if otherGestureRecognizer === scrollView.panGestureRecognizer {
            return false
        }
        if otherGestureRecognizer is UIScreenEdgePanGestureRecognizer {
            return false
        }
        return otherGestureRecognizer.view?.isDescendant(of: scrollView) == true
    }

    private func pruneRegistrations() {
        registrations.removeAll { $0.participant == nil }
    }
}

@MainActor
private enum TimelineRowPanGestureRouterRegistry {
    static let routers = NSMapTable<UIScrollView, TimelineRowPanGestureRouter>
        .weakToStrongObjects()

    static func router(for scrollView: UIScrollView) -> TimelineRowPanGestureRouter {
        if let router = routers.object(forKey: scrollView) {
            return router
        }
        let router = TimelineRowPanGestureRouter(scrollView: scrollView)
        routers.setObject(router, forKey: scrollView)
        return router
    }
}

@MainActor
func timelineRowGestureArbitrator(
    for scrollView: UIScrollView
) -> TimelineRowGestureArbitrator {
    TimelineRowPanGestureRouterRegistry.router(for: scrollView).arbitrator
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var currentView = superview
        while let view = currentView {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            currentView = view.superview
        }
        return nil
    }
}
