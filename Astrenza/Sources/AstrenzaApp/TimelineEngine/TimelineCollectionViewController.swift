import DesignSystem
import SwiftUI
import UIKit

struct TimelineCollectionViewControllerSurfaceState: Equatable, Sendable {
    var isViewLoaded: Bool
    var hasCollectionView: Bool
    var isAttachedToWindow: Bool
    var itemIDs: [TimelineEntryID]
}

@MainActor
final class TimelineCollectionViewController: UIViewController {
    private let accountID: AccountID
    private let feedID: FeedID
    private let timelineKey: TimelineKey
    private let theme: AppTheme
    private var pendingItemIDs: [TimelineEntryID]

    private let diagnosticsRecorder = TimelineDiagnosticsRecorder()
    private let visibleRangeTracker = TimelineVisibleRangeTracker()
    private let prefetchCoordinator = TimelinePrefetchCoordinator()
    private let resolveApplyCoordinator = TimelineResolveApplyCoordinator()
    private let positionRecorder: TimelinePositionRecorder

    private var collectionView: UICollectionView?
    private var dataSource: TimelineSnapshotCoordinator.DataSource?
    private var snapshotCoordinator: TimelineSnapshotCoordinator?

    private lazy var cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, TimelineEntryID> { [theme] cell, _, entryID in
        cell.contentConfiguration = UIHostingConfiguration {
            TimelinePlaceholderRow(entryID: entryID)
                .appTheme(theme)
        }
        cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
    }

    init(
        accountID: AccountID = .debug,
        feedID: FeedID = .debugHome,
        timelineKey: TimelineKey = .home,
        initialItemIDs: [TimelineEntryID] = TimelineEntryID.debugItems,
        theme: AppTheme = .system
    ) {
        self.accountID = accountID
        self.feedID = feedID
        self.timelineKey = timelineKey
        self.theme = theme
        self.pendingItemIDs = initialItemIDs
        self.positionRecorder = TimelinePositionRecorder(
            accountID: accountID,
            feedID: feedID,
            timelineKey: timelineKey
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable for TimelineCollectionViewController")
    }

    var surfaceState: TimelineCollectionViewControllerSurfaceState {
        TimelineCollectionViewControllerSurfaceState(
            isViewLoaded: isViewLoaded,
            hasCollectionView: collectionView != nil,
            isAttachedToWindow: viewIfLoaded?.window != nil,
            itemIDs: snapshotCoordinator?.currentItemIDs ?? pendingItemIDs
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(theme.color(.timelineBackground))

        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: Self.makeLayout(theme: theme)
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = UIColor(theme.color(.timelineBackground))
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delegate = self
        collectionView.prefetchDataSource = self

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let dataSource = makeDataSource(collectionView: collectionView)
        let snapshotCoordinator = TimelineSnapshotCoordinator(
            dataSource: dataSource,
            positionRecorder: positionRecorder,
            visibleRangeTracker: visibleRangeTracker,
            diagnosticsRecorder: diagnosticsRecorder
        )

        self.collectionView = collectionView
        self.dataSource = dataSource
        self.snapshotCoordinator = snapshotCoordinator

        snapshotCoordinator.applyPreservingPosition(
            itemIDs: pendingItemIDs,
            reason: .initialRestore,
            in: collectionView,
            animatingDifferences: false
        )
    }

    func apply(
        itemIDs: [TimelineEntryID],
        reason: TimelineSnapshotReason,
        animatingDifferences: Bool = true
    ) {
        pendingItemIDs = itemIDs
        guard
            let collectionView,
            let snapshotCoordinator
        else {
            return
        }

        snapshotCoordinator.applyPreservingPosition(
            itemIDs: itemIDs,
            reason: reason,
            in: collectionView,
            animatingDifferences: animatingDifferences
        )
    }

    func applyResolved(
        resolvedIDs: [TimelineEntryID],
        reason: ResolveApplyReason,
        animatingDifferences: Bool = true
    ) {
        guard
            let collectionView,
            let snapshotCoordinator
        else {
            return
        }

        let intent = resolveApplyCoordinator.reconfigureIntent(
            resolvedIDs: resolvedIDs,
            existingIDs: snapshotCoordinator.currentItemIDs,
            reason: reason
        )
        resolveApplyCoordinator.applyResolvedUpdates(
            intent: intent,
            snapshotCoordinator: snapshotCoordinator,
            in: collectionView,
            animatingDifferences: animatingDifferences
        )
    }

    private func makeDataSource(collectionView: UICollectionView) -> TimelineSnapshotCoordinator.DataSource {
        let cellRegistration = cellRegistration
        return TimelineSnapshotCoordinator.DataSource(collectionView: collectionView) { collectionView, indexPath, entryID in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: entryID
            )
        }
    }

    private static func makeLayout(theme: AppTheme) -> UICollectionViewLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = UIColor(theme.color(.timelineBackground))
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private func entryIDs(for indexPaths: [IndexPath]) -> [TimelineEntryID] {
        indexPaths.compactMap { dataSource?.itemIdentifier(for: $0) }
    }
}

extension TimelineCollectionViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let collectionView else {
            return
        }

        _ = visibleRangeTracker.recordVisibleIndexPaths(in: collectionView) { [dataSource] indexPath in
            dataSource?.itemIdentifier(for: indexPath)
        }
    }
}

extension TimelineCollectionViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        _ = prefetchCoordinator.preparePrefetch(for: entryIDs(for: indexPaths))
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        prefetchCoordinator.cancelPrefetch(for: entryIDs(for: indexPaths))
    }
}
