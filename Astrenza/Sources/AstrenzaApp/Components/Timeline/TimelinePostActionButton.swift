import SwiftUI
import UIKit

struct TimelinePostActionButton: View {
    let inactiveSystemName: String
    let activeSystemName: String
    let isActive: Bool
    let accessibilityLabel: String
    var accessibilityIdentifier: String?
    var supportsLongPressDrag = false
    var action: () -> Void = {}
    var onLongPress: () -> Void = {}
    var onLongPressDragChanged: (CGPoint) -> Void = { _ in }
    var onLongPressDragEnded: (CGPoint?) -> Void = { _ in }

    var body: some View {
        UIKitTimelinePostActionButton(
            systemName: isActive ? activeSystemName : inactiveSystemName,
            isActive: isActive,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier,
            supportsLongPressDrag: supportsLongPressDrag,
            action: action,
            onLongPress: onLongPress,
            onLongPressDragChanged: onLongPressDragChanged,
            onLongPressDragEnded: onLongPressDragEnded
        )
        .frame(height: AstrenzaTimelineMetrics.actionHeight)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }
}

private struct UIKitTimelinePostActionButton: UIViewRepresentable {
    let systemName: String
    let isActive: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String?
    let supportsLongPressDrag: Bool
    let action: () -> Void
    let onBegan: () -> Void
    let onMoved: (CGPoint) -> Void
    let onEnded: (CGPoint?) -> Void

    init(
        systemName: String,
        isActive: Bool,
        accessibilityLabel: String,
        accessibilityIdentifier: String?,
        supportsLongPressDrag: Bool,
        action: @escaping () -> Void,
        onLongPress: @escaping () -> Void,
        onLongPressDragChanged: @escaping (CGPoint) -> Void,
        onLongPressDragEnded: @escaping (CGPoint?) -> Void
    ) {
        self.systemName = systemName
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.supportsLongPressDrag = supportsLongPressDrag
        self.action = action
        self.onBegan = onLongPress
        self.onMoved = onLongPressDragChanged
        self.onEnded = onLongPressDragEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ActionButtonControl {
        let control = ActionButtonControl()
        control.backgroundColor = .clear
        control.isAccessibilityElement = true
        control.accessibilityTraits = [.button]
        control.imageView.contentMode = .center
        control.addSubview(control.imageView)

        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapRecognizer.cancelsTouchesInView = true
        tapRecognizer.delegate = context.coordinator
        control.addGestureRecognizer(tapRecognizer)

        if supportsLongPressDrag {
            let longPressRecognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
            longPressRecognizer.minimumPressDuration = 0.42
            longPressRecognizer.allowableMovement = 14
            longPressRecognizer.cancelsTouchesInView = false
            longPressRecognizer.delaysTouchesBegan = false
            longPressRecognizer.delaysTouchesEnded = false
            longPressRecognizer.delegate = context.coordinator
            control.addGestureRecognizer(longPressRecognizer)
        }

        return control
    }

    func updateUIView(_ uiView: ActionButtonControl, context: Context) {
        context.coordinator.parent = self
        uiView.update(systemName: systemName, isActive: isActive)
        uiView.accessibilityLabel = accessibilityLabel
        uiView.accessibilityIdentifier = accessibilityIdentifier
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: UIKitTimelinePostActionButton
        private var didBegin = false
        private weak var lockedScrollView: UIScrollView?
        private var lockedScrollViewWasEnabled: Bool?

        init(parent: UIKitTimelinePostActionButton) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.action()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard parent.supportsLongPressDrag else { return }

            switch recognizer.state {
            case .began:
                didBegin = true
                lockScrollViewIfNeeded(from: recognizer.view)
                parent.onBegan()
                parent.onMoved(windowLocation(for: recognizer))
            case .changed:
                guard didBegin else { return }
                parent.onMoved(windowLocation(for: recognizer))
            case .ended:
                parent.onEnded(didBegin ? windowLocation(for: recognizer) : nil)
                didBegin = false
                unlockScrollViewIfNeeded()
            case .cancelled, .failed:
                parent.onEnded(nil)
                didBegin = false
                unlockScrollViewIfNeeded()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private func windowLocation(for recognizer: UILongPressGestureRecognizer) -> CGPoint {
            guard let view = recognizer.view else {
                return recognizer.location(in: nil)
            }

            return view.convert(recognizer.location(in: view), to: nil)
        }

        private func lockScrollViewIfNeeded(from view: UIView?) {
            guard lockedScrollViewWasEnabled == nil,
                  let scrollView = view?.enclosingScrollView()
            else { return }

            lockedScrollView = scrollView
            lockedScrollViewWasEnabled = scrollView.isScrollEnabled
            scrollView.isScrollEnabled = false
        }

        private func unlockScrollViewIfNeeded() {
            guard let lockedScrollViewWasEnabled,
                  let lockedScrollView
            else { return }

            lockedScrollView.isScrollEnabled = lockedScrollViewWasEnabled
            self.lockedScrollViewWasEnabled = nil
            self.lockedScrollView = nil
        }
    }

    final class ActionButtonControl: UIControl {
        let imageView = UIImageView()
        private var configuredSystemName: String?
        private var configuredIsActive: Bool?

        override func layoutSubviews() {
            super.layoutSubviews()
            imageView.frame = bounds
        }

        func update(systemName: String, isActive: Bool) {
            guard configuredSystemName != systemName || configuredIsActive != isActive else {
                return
            }
            configuredSystemName = systemName
            configuredIsActive = isActive

            let configuration = UIImage.SymbolConfiguration(
                pointSize: AstrenzaTimelineMetrics.actionIconSize,
                weight: isActive ? .bold : .semibold
            )
            imageView.image = UIImage(systemName: systemName, withConfiguration: configuration)
            imageView.tintColor = isActive ? UIColor.label : UIColor.secondaryLabel
            imageView.preferredSymbolConfiguration = configuration
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
