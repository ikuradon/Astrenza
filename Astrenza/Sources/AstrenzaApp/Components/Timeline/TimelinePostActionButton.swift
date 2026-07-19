import SwiftUI
import UIKit

struct TimelinePostActionButton: View {
    let inactiveSystemName: String
    let activeSystemName: String
    let isActive: Bool
    let accessibilityLabel: String
    var accessibilityIdentifier: String?
    var menuKind: TimelinePostActionKind?
    var showsMenuAsPrimaryAction = false
    var action: () -> Void = {}
    var onMenuSelection: (TimelinePostActionMenuSelection) -> Void = { _ in }

    var body: some View {
        UIKitTimelinePostActionButton(
            systemName: isActive ? activeSystemName : inactiveSystemName,
            isActive: isActive,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier,
            menuKind: menuKind,
            showsMenuAsPrimaryAction: showsMenuAsPrimaryAction,
            action: action,
            onMenuSelection: onMenuSelection
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
    let menuKind: TimelinePostActionKind?
    let showsMenuAsPrimaryAction: Bool
    let action: () -> Void
    let onMenuSelection: (TimelinePostActionMenuSelection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ActionButtonControl {
        let control = ActionButtonControl()
        control.backgroundColor = .clear
        control.isAccessibilityElement = true
        control.accessibilityTraits = [.button]
        control.imageView?.contentMode = .center
        control.addAction(
            UIAction { [weak coordinator = context.coordinator] _ in
                coordinator?.performPrimaryAction()
            },
            for: .primaryActionTriggered
        )
        return control
    }

    func updateUIView(_ uiView: ActionButtonControl, context: Context) {
        context.coordinator.parent = self
        uiView.update(systemName: systemName, isActive: isActive)
        uiView.accessibilityLabel = accessibilityLabel
        uiView.accessibilityIdentifier = accessibilityIdentifier
        uiView.updateMenu(
            kind: menuKind,
            showsAsPrimaryAction: showsMenuAsPrimaryAction,
            makeMenu: context.coordinator.makeMenu
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: UIKitTimelinePostActionButton

        init(parent: UIKitTimelinePostActionButton) {
            self.parent = parent
        }

        func performPrimaryAction() {
            parent.action()
        }

        func makeMenu(for kind: TimelinePostActionKind) -> UIMenu {
            TimelinePostActionMenuBuilder.make(kind: kind) { [weak self] selection in
                self?.parent.onMenuSelection(selection)
            }
        }
    }

    final class ActionButtonControl: UIButton {
        private var configuredSystemName: String?
        private var configuredIsActive: Bool?
        private var configuredMenuKind: TimelinePostActionKind?
        private var configuredShowsMenuAsPrimaryAction = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentHorizontalAlignment = .fill
            contentVerticalAlignment = .fill
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            imageView?.frame = bounds
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
            setImage(
                UIImage(systemName: systemName, withConfiguration: configuration),
                for: .normal
            )
            tintColor = isActive ? .label : .secondaryLabel
            imageView?.preferredSymbolConfiguration = configuration
        }

        func updateMenu(
            kind: TimelinePostActionKind?,
            showsAsPrimaryAction: Bool,
            makeMenu: (TimelinePostActionKind) -> UIMenu
        ) {
            let effectivePrimaryAction = kind != nil && showsAsPrimaryAction
            guard configuredMenuKind != kind ||
                    configuredShowsMenuAsPrimaryAction != effectivePrimaryAction
            else { return }

            configuredMenuKind = kind
            configuredShowsMenuAsPrimaryAction = effectivePrimaryAction
            menu = kind.map(makeMenu)
            self.showsMenuAsPrimaryAction = effectivePrimaryAction
        }
    }
}
