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
        context.coordinator.markerView = uiView
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TimelineRowPanGestureHost
        weak var markerView: UIView?
        private weak var scrollView: UIScrollView?
        private var recognizer: UIPanGestureRecognizer?
        private var beganInsideRow = false

        init(parent: TimelineRowPanGestureHost) {
            self.parent = parent
        }

        deinit {
            if let recognizer, let scrollView {
                DispatchQueue.main.async {
                    scrollView.removeGestureRecognizer(recognizer)
                }
            }
        }

        func attachIfNeeded(from markerView: UIView) {
            self.markerView = markerView
            guard let targetScrollView = markerView.enclosingScrollView() else { return }
            guard scrollView !== targetScrollView else { return }

            if let recognizer, let scrollView {
                scrollView.removeGestureRecognizer(recognizer)
            }

            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.minimumNumberOfTouches = 1
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            targetScrollView.addGestureRecognizer(recognizer)

            self.scrollView = targetScrollView
            self.recognizer = recognizer
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard parent.isEnabled, beganInsideRow else { return }
            let translation = recognizer.translation(in: scrollView).x

            switch recognizer.state {
            case .began, .changed:
                parent.onChanged(translation)
            case .ended:
                parent.onEnded(translation)
                beganInsideRow = false
            case .cancelled, .failed:
                parent.onEnded(0)
                beganInsideRow = false
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isEnabled,
                  let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer,
                  let markerView,
                  let scrollView
            else {
                return false
            }

            let locationInRow = panRecognizer.location(in: markerView)
            guard markerView.bounds.contains(locationInRow) else {
                beganInsideRow = false
                return false
            }

            let velocity = panRecognizer.velocity(in: scrollView)
            let horizontalSpeed = abs(velocity.x)
            let verticalSpeed = abs(velocity.y)
            beganInsideRow = horizontalSpeed > 120 && horizontalSpeed > verticalSpeed * 1.35
            return beganInsideRow
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard parent.isEnabled,
                  gestureRecognizer === recognizer,
                  beganInsideRow
            else { return false }

            return true
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
