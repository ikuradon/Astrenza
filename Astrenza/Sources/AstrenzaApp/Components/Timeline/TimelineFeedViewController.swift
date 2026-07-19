import SwiftUI
import UIKit

@MainActor
final class TimelineFeedViewController: UIViewController {
    private enum Section: Hashable {
        case main
    }

    private let anchorLineY: CGFloat = 72
    private let readLineY: CGFloat = 96
    private let topContentPadding: CGFloat = 72
    private let bottomContentPadding: CGFloat = 124
    private let pullRefreshTriggerOffset: CGFloat = -96
    private let viewportSaveInterval: TimeInterval = 0.25
    private let viewportSaveOffsetThreshold: CGFloat = 48
    private let cellReuseIdentifier = "timeline-entry"

    private var configuration: TimelineFeedCollectionConfiguration?
    private var entries: [TimelineFeedEntry] = []
    private var entriesByID: [TimelineFeedEntry.ID: TimelineFeedEntry] = [:]
    private var postOrderByID: [TimelinePost.ID: Int] = [:]
    private var readLinePositionByPostID:
        [TimelinePost.ID: TimelinePostReadLinePosition] = [:]
    private var restoreCoordinator = TimelineFeedViewportRestoreCoordinator()
    private var pendingPostSnapshotPosition =
        TimelineFeedSnapshotPosition.unchanged
    private var pendingPreservedAnchor: TimelineFeedVisibleAnchor?
    private var pendingRefreshAnchor: TimelineFeedVisibleAnchor?
    private var pullRefreshSourceRevision: Int?
    private var fetchingGapDirections:
        [TimelineGap.ID: TimelineGapFillDirection] = [:]
    private var lastScrollCommandID: UUID?
    private var lastSwipeSettings: TimelineSwipeSettings?
    private var initialViewportReadySourceIdentity: String?
    private var lastUnreadPillPlacement = HomeUnreadPillPlacement.hidden
    private var lastLoadedOlderPostID: TimelinePost.ID?
    private var lastSavedViewportAnchor: TimelineFeedVisibleAnchor?
    private var lastSavedViewportOffset: CGFloat = 0
    private var lastViewportSaveTime: TimeInterval = 0
    private var hasUserInteraction = false
    private var isApplyingSnapshot = false
    private var isProgrammaticScroll = false
    private var isUserScrollActive = false
    private var isPullRefreshArmed = false
    private var isPullRefreshing = false
    private var pullRefreshProgress: CGFloat = 0
    private var restoreRetryGeneration: UInt64 = 0
    private var missingRestoreAnchorAttempts = 0

    private lazy var collectionLayout = TimelineFeedSelfSizingLayout.make(
        topContentPadding: topContentPadding
    )

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: collectionLayout
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = true
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        // SwiftUIのintrinsic size通知をscroll中の再レイアウトへ直結させず、
        // diffable snapshotの更新をRow再計測の明示的な境界にする。
        collectionView.selfSizingInvalidation = .disabled
        collectionView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: bottomContentPadding,
            right: 0
        )
        collectionView.verticalScrollIndicatorInsets =
            collectionView.contentInset
        collectionView.keyboardDismissMode = .interactive
        collectionView.accessibilityIdentifier = "timeline.feed"
        collectionView.register(
            TimelineFeedHostingCollectionCell.self,
            forCellWithReuseIdentifier: cellReuseIdentifier
        )
        collectionView.delegate = self
        return collectionView
    }()

    private lazy var dataSource = makeDataSource()
    private lazy var menuCoordinator = TimelineFeedMenuCoordinator(
        owner: self,
        containerView: view
    )

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = UIColor(Color.astrenzaBackground)
        rootView.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: rootView.topAnchor),
            collectionView.leadingAnchor.constraint(
                equalTo: rootView.leadingAnchor
            ),
            collectionView.trailingAnchor.constraint(
                equalTo: rootView.trailingAnchor
            ),
            collectionView.bottomAnchor.constraint(
                equalTo: rootView.bottomAnchor
            ),
        ])
        view = rootView
        _ = dataSource
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        menuCoordinator.relayout()
        attemptPendingRestoreIfPossible()
        publishInitialViewportReadyIfPossible()
        publishUnreadPillPlacement()
    }

    func apply(_ nextConfiguration: TimelineFeedCollectionConfiguration) {
        loadViewIfNeeded()
        let previousConfiguration = configuration
        let sourceChanged = previousConfiguration?.sourceIdentity !=
            nextConfiguration.sourceIdentity
        configuration = nextConfiguration

        if sourceChanged {
            resetForSourceChange()
        }

        let previousRestoreRequest = restoreCoordinator.request
        restoreCoordinator.synchronize(
            sourceIdentity: nextConfiguration.sourceIdentity,
            state: nextConfiguration.viewportState,
            isRestoreProtected:
                nextConfiguration.viewportRestoreProtectionActive
        )
        if previousRestoreRequest != restoreCoordinator.request {
            missingRestoreAnchorAttempts = 0
        }
        configureMenuCoordinator()

        let swipeSettingsChanged = lastSwipeSettings !=
            nextConfiguration.swipeSettings
        let contentRevisionChanged = previousConfiguration?.sourceRevision !=
            nextConfiguration.sourceRevision
        lastSwipeSettings = nextConfiguration.swipeSettings
        if sourceChanged ||
            contentRevisionChanged ||
            swipeSettingsChanged {
            applyEntries(
                nextConfiguration.entries,
                forceVisibleReconfiguration:
                    contentRevisionChanged || swipeSettingsChanged,
                reconfigureAllVisible: swipeSettingsChanged
            )
        }

        if previousConfiguration?.unreadCountAnchorPostID !=
            nextConfiguration.unreadCountAnchorPostID {
            publishUnreadPillPlacement(force: true)
        }

        handleScrollCommandIfNeeded()
        attemptPendingRestoreIfPossible()
        publishInitialViewportReadyIfPossible()
    }

    func prepareForRemoval() {
        restoreRetryGeneration &+= 1
        missingRestoreAnchorAttempts = 0
        menuCoordinator.close()
        saveViewportStateIfPossible(force: true)
        setUserScrollActive(false)
    }

    private func makeDataSource()
        -> UICollectionViewDiffableDataSource<
            Section,
            TimelineFeedEntry.ID
        > {
        UICollectionViewDiffableDataSource(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, entryID in
            guard let self,
                  let entry = entriesByID[entryID],
                  let configuration
            else { return nil }

            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: cellReuseIdentifier,
                for: indexPath
            ) as? TimelineFeedHostingCollectionCell else { return nil }
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            let gapDirection = displayGapDirection(for: entryID)
            let isFetchingGap = fetchingGapDirections[entryID] != nil
            let isActionMenuPresented =
                menuCoordinator.openedPostID == entry.post?.id
            let hostedConfiguration = UIHostingConfiguration {
                TimelineHostedFeedEntryView(
                    entry: entry,
                    swipeSettings: configuration.swipeSettings,
                    isActionMenuPresented: isActionMenuPresented,
                    gapDirection: gapDirection,
                    isFetchingGap: isFetchingGap,
                    onActionEvent: { [weak self] event in
                        self?.handlePostActionEvent(event)
                    },
                    onOpenPost: { [weak self] post in
                        self?.openPost(post)
                    },
                    onOpenProfile: configuration.onOpenProfile,
                    onReplyPost: configuration.onReplyPost,
                    onOpenMedia: configuration.onOpenMedia,
                    onOpenURL: configuration.onOpenURL,
                    onDismissActionMenu: { [weak self] in
                        self?.menuCoordinator.close()
                    },
                    onBackfillGap: { [weak self] gap in
                        self?.requestBackfill(gap)
                    }
                )
            }
            .margins(.all, 0)
            .background { Color.astrenzaBackground }
            cell.configure(
                contentConfiguration: hostedConfiguration,
                sizingIdentity: TimelineFeedCellSizingIdentity(
                    entryID: entryID,
                    renderFingerprint:
                        TimelineRenderFingerprint.entry(entry),
                    swipeSettings: configuration.swipeSettings,
                    isActionMenuPresented: isActionMenuPresented,
                    gapDirection: gapDirection,
                    isFetchingGap: isFetchingGap
                )
            )
            return cell
        }
    }

    private func configureMenuCoordinator() {
        guard let configuration else { return }
        menuCoordinator.configure(
            actionMenuTopClearance: configuration.actionMenuTopClearance,
            postProvider: { [weak self] postID in
                self?.entriesByID[postID]?.post
            },
            onPostActionChoice: configuration.onPostActionChoice,
            onOpenStateChanged: { [weak self] isOpen, affectedPostIDs in
                guard let self else { return }
                collectionView.isScrollEnabled = !isOpen
                reconfigureEntries(Array(affectedPostIDs))
            }
        )
    }

    private func resetForSourceChange() {
        restoreRetryGeneration &+= 1
        menuCoordinator.close()
        entries = []
        entriesByID = [:]
        postOrderByID = [:]
        readLinePositionByPostID = [:]
        pendingPreservedAnchor = nil
        pendingRefreshAnchor = nil
        pullRefreshSourceRevision = nil
        fetchingGapDirections = [:]
        lastScrollCommandID = nil
        initialViewportReadySourceIdentity = nil
        lastUnreadPillPlacement = .hidden
        lastLoadedOlderPostID = nil
        lastSavedViewportAnchor = nil
        lastSavedViewportOffset = 0
        lastViewportSaveTime = 0
        hasUserInteraction = false
        isProgrammaticScroll = true
        collectionView.setContentOffset(.zero, animated: false)
        isProgrammaticScroll = false
    }

    private func applyEntries(
        _ newEntries: [TimelineFeedEntry],
        forceVisibleReconfiguration: Bool,
        reconfigureAllVisible: Bool = false
    ) {
        let oldIDs = entries.map(\.id)
        let newIDs = newEntries.map(\.id)
        let structureChanged = oldIDs != newIDs
        guard structureChanged || forceVisibleReconfiguration else {
            entries = newEntries
            entriesByID = Dictionary(
                uniqueKeysWithValues: newEntries.map { ($0.id, $0) }
            )
            rebuildPostOrder()
            return
        }

        let oldIDSet = Set(oldIDs)
        let newIDSet = Set(newIDs)
        let visibleIDs = Set(
            collectionView.indexPathsForVisibleItems.compactMap {
                dataSource.itemIdentifier(for: $0)
            }
        )
        let oldFingerprintsByID = Dictionary(
            uniqueKeysWithValues: entries.map {
                ($0.id, TimelineRenderFingerprint.entry($0))
            }
        )
        let changedCommonIDs: Set<TimelineFeedEntry.ID> = Set(
            newEntries.compactMap { entry -> TimelineFeedEntry.ID? in
                guard let oldFingerprint = oldFingerprintsByID[entry.id],
                      oldFingerprint != TimelineRenderFingerprint.entry(entry)
                else { return nil }
                return entry.id
            }
        )
        let reconfiguredIDs = forceVisibleReconfiguration
            ? visibleIDs
                .intersection(oldIDSet)
                .intersection(newIDSet)
                .intersection(
                    reconfigureAllVisible
                        ? visibleIDs
                        : changedCommonIDs
                )
            : []

        let visibleAnchor = captureVisibleAnchor()
        pendingPostSnapshotPosition = TimelineFeedViewportMutationPlanner
            .position(
                for: TimelineFeedViewportMutationInput(
                    oldIDs: oldIDs,
                    newIDs: newIDs,
                    visibleAnchor: visibleAnchor,
                    refreshAnchor: pendingRefreshAnchor,
                    isPullRefreshing: isPullRefreshing,
                    followsRealtimeEntries:
                        configuration?.followsRealtimeEntries == true,
                    isRestoreProtected:
                        configuration?.viewportRestoreProtectionActive == true,
                    isRestoreBlocked:
                        restoreCoordinator.blocksPersistence
                )
            )
        entries = newEntries
        entriesByID = Dictionary(
            uniqueKeysWithValues: newEntries.map { ($0.id, $0) }
        )
        rebuildPostOrder()
        fetchingGapDirections = fetchingGapDirections.filter {
            entriesByID[$0.key] != nil
        }

        var snapshot = NSDiffableDataSourceSnapshot<
            Section,
            TimelineFeedEntry.ID
        >()
        snapshot.appendSections([.main])
        snapshot.appendItems(newIDs, toSection: .main)
        if !reconfiguredIDs.isEmpty {
            snapshot.reconfigureItems(Array(reconfiguredIDs))
        }

        isApplyingSnapshot = true
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            isApplyingSnapshot = false
            view.layoutIfNeeded()
            applyPostSnapshotPosition()
            if pullRefreshSourceRevision != configuration?.sourceRevision {
                pendingRefreshAnchor = nil
                pullRefreshSourceRevision = nil
            }
            attemptPendingRestoreIfPossible()
            publishInitialViewportReadyIfPossible()
            updateReadLinePositions()
            publishUnreadPillPlacement(force: true)
        }
    }

    private func applyPostSnapshotPosition() {
        let position = pendingPostSnapshotPosition
        pendingPostSnapshotPosition = .unchanged
        switch position {
        case .unchanged:
            break
        case .preserve(let anchor):
            preserve(anchor)
        case .newest:
            setContentOffset(0)
        }
    }

    private func rebuildPostOrder() {
        var nextOrder: [TimelinePost.ID: Int] = [:]
        nextOrder.reserveCapacity(entries.count)
        for entry in entries {
            guard let postID = entry.post?.id else { continue }
            nextOrder[postID] = nextOrder.count
        }
        postOrderByID = nextOrder
        readLinePositionByPostID = readLinePositionByPostID.filter {
            nextOrder[$0.key] != nil
        }
    }

    private func handleScrollCommandIfNeeded() {
        guard let scrollCommand = configuration?.scrollCommand,
              scrollCommand.id != lastScrollCommandID
        else { return }
        lastScrollCommandID = scrollCommand.id
        restoreRetryGeneration &+= 1
        switch scrollCommand.target {
        case .top:
            setContentOffset(0)
        case .viewport(let state):
            positionViewport(state)
        }
    }

    private func attemptPendingRestoreIfPossible() {
        guard !isApplyingSnapshot,
              view.bounds.height > 0
        else { return }

        let request: TimelineFeedViewportRestoreRequest
        switch restoreCoordinator.phase {
        case .ready:
            return
        case .awaitingContent:
            guard let pendingRequest =
                restoreCoordinator.beginPositioning()
            else { return }
            request = pendingRequest
            guard coarsePositionViewport(request.state) else {
                handleMissingRestoreAnchor(request)
                return
            }
            scheduleRestoreRetry()
            return
        case .positioning(let positioningRequest):
            request = positioningRequest
        }

        guard let indexPath = dataSource.indexPath(
            for: request.state.anchorPostID
        ), entriesByID[request.state.anchorPostID]?.post != nil else {
            handleMissingRestoreAnchor(request)
            return
        }
        missingRestoreAnchorAttempts = 0
        guard let anchorRect = frameForEntry(at: indexPath) else {
            restoreCoordinator.retryPositioning()
            scheduleRestoreRetry()
            return
        }
        let targetOffset = targetContentOffset(
            anchorMinY: anchorRect.minY,
            anchorOffset: request.state.anchorOffset
        )
        guard collectionView.cellForItem(at: indexPath) != nil else {
            setContentOffsetWithoutLayout(targetOffset)
            scheduleRestoreRetry()
            return
        }

        if restoreCoordinator.complete(
            request: request,
            actualContentOffset: collectionView.contentOffset.y,
            targetContentOffset: targetOffset
        ) {
            restoreRetryGeneration &+= 1
            configuration?.onScrollOffsetChanged(
                collectionView.contentOffset.y
            )
            configuration?.onViewportRestoreCompleted(
                collectionView.contentOffset.y
            )
            publishInitialViewportReadyIfPossible()
            publishUnreadPillPlacement(force: true)
        } else {
            setContentOffsetWithoutLayout(targetOffset)
            scheduleRestoreRetry()
        }
    }

    private func coarsePositionViewport(
        _ state: TimelineViewportState
    ) -> Bool {
        guard let indexPath = dataSource.indexPath(for: state.anchorPostID),
              entriesByID[state.anchorPostID]?.post != nil
        else { return false }

        guard let estimatedAnchorMinY = frameForEntry(
            at: indexPath
        )?.minY else { return false }
        setContentOffsetWithoutLayout(
            targetContentOffset(
                anchorMinY: estimatedAnchorMinY,
                anchorOffset: state.anchorOffset
            )
        )
        return true
    }

    private func handleMissingRestoreAnchor(
        _ request: TimelineFeedViewportRestoreRequest
    ) {
        missingRestoreAnchorAttempts += 1
        guard TimelineFeedViewportRestorePolicy
            .shouldFallbackForMissingAnchor(
                hasContent: !entries.isEmpty,
                attempt: missingRestoreAnchorAttempts
            )
        else {
            restoreCoordinator.retryPositioning()
            if !entries.isEmpty {
                scheduleRestoreRetry()
            }
            return
        }

        guard restoreCoordinator.completeUsingFallback(request: request)
        else { return }
        restoreRetryGeneration &+= 1
        setContentOffset(request.state.contentOffset)
        let actualOffset = collectionView.contentOffset.y
        configuration?.onScrollOffsetChanged(actualOffset)
        configuration?.onViewportRestoreCompleted(actualOffset)
        publishInitialViewportReadyIfPossible()
        publishUnreadPillPlacement(force: true)
    }

    @discardableResult
    private func positionViewport(_ state: TimelineViewportState) -> Bool {
        guard let indexPath = dataSource.indexPath(for: state.anchorPostID),
              entriesByID[state.anchorPostID]?.post != nil
        else { return false }

        isProgrammaticScroll = true
        var didPosition = false
        UIView.performWithoutAnimation {
            collectionView.scrollToItem(
                at: indexPath,
                at: .top,
                animated: false
            )
            collectionView.layoutIfNeeded()
            guard let anchorRect = frameForEntry(at: indexPath) else {
                return
            }
            collectionView.setContentOffset(
                CGPoint(
                    x: 0,
                    y: targetContentOffset(
                        anchorMinY: anchorRect.minY,
                        anchorOffset: state.anchorOffset
                    )
                ),
                animated: false
            )
            collectionView.layoutIfNeeded()
            didPosition = true
        }
        isProgrammaticScroll = false
        return didPosition
    }

    private func scheduleRestoreRetry() {
        restoreRetryGeneration &+= 1
        let generation = restoreRetryGeneration
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.016
        ) { [weak self] in
            guard let self,
                  restoreRetryGeneration == generation
            else { return }
            attemptPendingRestoreIfPossible()
        }
    }

    private func publishInitialViewportReadyIfPossible() {
        guard let configuration,
              initialViewportReadySourceIdentity !=
                configuration.sourceIdentity,
              !isApplyingSnapshot,
              !restoreCoordinator.blocksPersistence,
              view.window != nil,
              view.bounds.height > 0
        else { return }

        initialViewportReadySourceIdentity =
            configuration.sourceIdentity
        configuration.onInitialViewportReady()
    }

    private func frameForEntry(at indexPath: IndexPath) -> CGRect? {
        collectionView.collectionViewLayout
            .layoutAttributesForItem(at: indexPath)?
            .frame
    }

    private func captureVisibleAnchor() -> TimelineFeedVisibleAnchor? {
        let lineInContent = collectionView.contentOffset.y + anchorLineY
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
            .sorted()
        for indexPath in visibleIndexPaths {
            guard let entryID = dataSource.itemIdentifier(for: indexPath),
                  entriesByID[entryID]?.post != nil,
                  let rect = frameForEntry(at: indexPath)
            else { continue }
            guard rect.maxY > lineInContent else { continue }
            return TimelineFeedVisibleAnchor(
                postID: entryID,
                offset: max(0, lineInContent - rect.minY)
            )
        }
        return nil
    }

    private func preserve(_ anchor: TimelineFeedVisibleAnchor) {
        guard let indexPath = dataSource.indexPath(for: anchor.postID) else {
            return
        }
        collectionView.layoutIfNeeded()
        guard let rect = frameForEntry(at: indexPath) else { return }
        setContentOffset(
            targetContentOffset(
                anchorMinY: rect.minY,
                anchorOffset: anchor.offset
            )
        )
    }

    private func targetContentOffset(
        anchorMinY: CGFloat,
        anchorOffset: CGFloat
    ) -> CGFloat {
        TimelineFeedViewportRestorePolicy.targetContentOffset(
            anchorMinY: anchorMinY,
            anchorOffset: anchorOffset,
            anchorLineY: anchorLineY,
            minimumOffset: minimumContentOffset,
            maximumOffset: maximumContentOffset
        )
    }

    private var minimumContentOffset: CGFloat {
        -collectionView.adjustedContentInset.top
    }

    private var maximumContentOffset: CGFloat {
        max(
            minimumContentOffset,
            collectionView.contentSize.height +
                collectionView.adjustedContentInset.bottom -
                collectionView.bounds.height
        )
    }

    private func setContentOffset(_ y: CGFloat) {
        isProgrammaticScroll = true
        UIView.performWithoutAnimation {
            collectionView.setContentOffset(
                CGPoint(
                    x: 0,
                    y: min(max(y, minimumContentOffset), maximumContentOffset)
                ),
                animated: false
            )
            collectionView.layoutIfNeeded()
        }
        isProgrammaticScroll = false
    }

    private func setContentOffsetWithoutLayout(_ y: CGFloat) {
        isProgrammaticScroll = true
        UIView.performWithoutAnimation {
            collectionView.setContentOffset(
                CGPoint(
                    x: 0,
                    y: min(
                        max(y, minimumContentOffset),
                        maximumContentOffset
                    )
                ),
                animated: false
            )
        }
        isProgrammaticScroll = false
    }

    private func saveViewportStateIfPossible(force: Bool = false) {
        guard let configuration,
              TimelineFeedViewportRestorePolicy.canSaveViewport(
                hasUserInteraction: hasUserInteraction,
                isRestoreBlocked: restoreCoordinator.blocksPersistence,
                isProgrammaticScroll: isProgrammaticScroll
              ),
              let anchor = captureVisibleAnchor()
        else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let offset = collectionView.contentOffset.y
        if !force,
           now - lastViewportSaveTime < viewportSaveInterval {
            return
        }
        let sameAnchor = lastSavedViewportAnchor?.postID == anchor.postID
        let anchorDelta = abs(
            (lastSavedViewportAnchor?.offset ?? anchor.offset) - anchor.offset
        )
        let offsetDelta = abs(lastSavedViewportOffset - offset)
        if !force,
           sameAnchor,
           anchorDelta < 1,
           offsetDelta < viewportSaveOffsetThreshold {
            return
        }

        lastSavedViewportAnchor = anchor
        lastSavedViewportOffset = offset
        lastViewportSaveTime = now
        configuration.onViewportStateChanged(
            TimelineViewportState(
                accountID: configuration.viewportIdentity.accountID,
                timelineKey: configuration.viewportIdentity.timelineKey,
                anchorPostID: anchor.postID,
                anchorOffset: anchor.offset,
                contentOffset: offset,
                updatedAt: Date()
            )
        )
    }

    private func updateReadLinePositions() {
        guard let configuration else { return }
        var crossedPostIDs: [TimelinePost.ID] = []
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let postID = dataSource.itemIdentifier(for: indexPath),
                  entriesByID[postID]?.post != nil,
                  let rect = frameForEntry(at: indexPath)
            else { continue }
            let minY = rect.minY - collectionView.contentOffset.y
            let position: TimelinePostReadLinePosition =
                minY <= readLineY ? .aboveOrAt : .below
            let previous = readLinePositionByPostID.updateValue(
                position,
                forKey: postID
            )
            if TimelineReadLineCrossingPolicy.advancesReadBoundary(
                previous: previous,
                current: position,
                isUserScrollActive: isUserScrollActive
            ) {
                crossedPostIDs.append(postID)
            }
        }
        guard !crossedPostIDs.isEmpty else { return }
        crossedPostIDs.sort {
            (postOrderByID[$0] ?? .max) < (postOrderByID[$1] ?? .max)
        }
        configuration.onPostsCrossedReadLineTowardNewer(crossedPostIDs)
    }

    private func publishUnreadPillPlacement(force: Bool = false) {
        guard let configuration else { return }
        let anchorPostID = configuration.unreadCountAnchorPostID
        let anchorMinY: CGFloat?
        if let anchorPostID,
           let indexPath = dataSource.indexPath(for: anchorPostID),
           let frame = frameForEntry(at: indexPath) {
            anchorMinY = frame.minY - collectionView.contentOffset.y
        } else {
            anchorMinY = nil
        }
        let placement = HomeUnreadPillPlacementPolicy.resolve(
            anchorPostID: anchorPostID,
            anchorMinY: anchorMinY,
            postOrderByID: postOrderByID,
            readablePostIDs: readablePostIDs,
            pinLineY: anchorLineY
        )
        guard force || placement != lastUnreadPillPlacement else { return }
        lastUnreadPillPlacement = placement
        configuration.onUnreadPillPlacementChanged(placement)
    }

    private var readablePostIDs: [TimelinePost.ID] {
        collectionView.indexPathsForVisibleItems.compactMap { indexPath in
            guard let postID = dataSource.itemIdentifier(for: indexPath),
                  entriesByID[postID]?.post != nil,
                  let rect = frameForEntry(at: indexPath)
            else { return nil }
            let frame = rect.offsetBy(
                dx: 0,
                dy: -collectionView.contentOffset.y
            )
            return frame.minY <= readLineY && frame.maxY > 0
                ? postID
                : nil
        }
    }

    private func handlePostActionEvent(_ event: TimelinePostActionEvent) {
        menuCoordinator.handle(
            event,
            sourceFrame: actionButtonFrame(
                postID: event.postID,
                kind: event.kind
            )
        )
    }

    private func actionButtonFrame(
        postID: TimelinePost.ID,
        kind: TimelinePostActionKind
    ) -> CGRect? {
        guard let indexPath = dataSource.indexPath(for: postID),
              let cell = collectionView.cellForItem(at: indexPath)
        else { return nil }
        let identifier: String
        switch kind {
        case .repost:
            identifier = "timeline.action.repost.\(postID)"
        case .favorite:
            identifier = "timeline.action.favorite.\(postID)"
        case .more:
            identifier = "timeline.action.more.\(postID)"
        }
        guard let button = cell.descendant(
            accessibilityIdentifier: identifier
        ) else { return nil }
        return button.convert(button.bounds, to: view)
    }

    private func openPost(_ post: TimelinePost) {
        if menuCoordinator.isOpen {
            menuCoordinator.close()
        } else {
            configuration?.onOpenPost(post)
        }
    }

    private func displayGapDirection(
        for entryID: TimelineFeedEntry.ID
    ) -> TimelineGapFillDirection {
        if let fetchingDirection = fetchingGapDirections[entryID] {
            return fetchingDirection
        }

        guard let gapIndex = entries.firstIndex(where: {
            $0.id == entryID
        }) else {
            return .older
        }

        let referencePostID = lastSavedViewportAnchor?.postID
            ?? configuration?.viewportState?.anchorPostID
        guard let referencePostID,
              let referenceIndex = entries.firstIndex(where: {
                  $0.post?.id == referencePostID
              })
        else { return .older }

        return gapIndex < referenceIndex ? .newer : .older
    }

    private func interactionGapDirection(
        for entryID: TimelineFeedEntry.ID
    ) -> TimelineGapFillDirection {
        guard let indexPath = dataSource.indexPath(for: entryID),
              let cell = collectionView.cellForItem(at: indexPath)
        else { return displayGapDirection(for: entryID) }

        let rect = cell.convert(cell.bounds, to: view)
        return rect.midY < view.bounds.height / 2 ? .newer : .older
    }

    private func requestBackfill(_ gap: TimelineGap) {
        guard fetchingGapDirections[gap.id] == nil else { return }
        let direction = interactionGapDirection(for: gap.id)
        fetchingGapDirections[gap.id] = direction
        reconfigureEntries([gap.id])

        if let onBackfillGap = configuration?.onBackfillGap {
            Task { @MainActor [weak self] in
                _ = await onBackfillGap(gap, direction)
                try? await Task.sleep(for: .milliseconds(750))
                guard let self else { return }
                fetchingGapDirections[gap.id] = nil
                reconfigureEntries([gap.id])
            }
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            self?.replaceMockGap(gap, direction: direction)
        }
    }

    private func replaceMockGap(
        _ gap: TimelineGap,
        direction: TimelineGapFillDirection
    ) {
        guard let index = entries.firstIndex(where: { $0.id == gap.id })
        else { return }
        var replacement = entries
        replacement.replaceSubrange(
            index...index,
            with: gap.backfilledPosts.map(TimelineFeedEntry.post)
        )
        fetchingGapDirections[gap.id] = nil
        applyEntries(replacement, forceVisibleReconfiguration: false)
    }

    private func reconfigureEntries(_ entryIDs: [TimelineFeedEntry.ID]) {
        let currentIDs = Set(dataSource.snapshot().itemIdentifiers)
        let validIDs = entryIDs.filter { currentIDs.contains($0) }
        guard !validIDs.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(validIDs)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func updatePullRefresh(offset: CGFloat) {
        guard configuration?.onRefresh != nil else { return }
        let progress = min(
            max(
                abs(min(offset, 0)) / abs(pullRefreshTriggerOffset),
                0
            ),
            1
        )
        if !isPullRefreshing {
            pullRefreshProgress = progress
        }
        if isUserScrollActive && offset <= pullRefreshTriggerOffset {
            isPullRefreshArmed = true
        }
        publishPullRefreshPresentation()
    }

    private func beginPullRefreshIfNeeded() {
        guard isPullRefreshArmed,
              !isPullRefreshing,
              let onRefresh = configuration?.onRefresh
        else {
            isPullRefreshArmed = false
            if !isPullRefreshing {
                pullRefreshProgress = 0
                publishPullRefreshPresentation()
            }
            return
        }

        isPullRefreshArmed = false
        isPullRefreshing = true
        pullRefreshProgress = 1
        pendingRefreshAnchor = captureVisibleAnchor()
        pullRefreshSourceRevision = configuration?.sourceRevision
        publishPullRefreshPresentation()

        Task { @MainActor [weak self] in
            let expectsSourceChange = await onRefresh()
            guard let self else { return }
            if !expectsSourceChange {
                pendingRefreshAnchor = nil
                pullRefreshSourceRevision = nil
            }
            isPullRefreshing = false
            pullRefreshProgress = 0
            publishPullRefreshPresentation()
        }
    }

    private func publishPullRefreshPresentation() {
        configuration?.onPullRefreshPresentationChanged(
            TimelinePullRefreshPresentation(
                isRefreshing: isPullRefreshing,
                progress: pullRefreshProgress
            )
        )
    }

    private func setUserScrollActive(_ isActive: Bool) {
        guard isUserScrollActive != isActive else { return }
        isUserScrollActive = isActive
        configuration?.onScrollActivityChanged(isActive)
    }
}

extension TimelineFeedViewController: UICollectionViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        hasUserInteraction = true
        setUserScrollActive(true)
        menuCoordinator.close()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isProgrammaticScroll,
              !restoreCoordinator.blocksPersistence
        else { return }

        let offset = scrollView.contentOffset.y
        configuration?.onScrollOffsetChanged(offset)
        updatePullRefresh(offset: offset)
        updateReadLinePositions()
        publishUnreadPillPlacement()
        saveViewportStateIfPossible()
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        beginPullRefreshIfNeeded()
        if !decelerate {
            setUserScrollActive(false)
            saveViewportStateIfPossible(force: true)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        setUserScrollActive(false)
        saveViewportStateIfPossible(force: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let postID = dataSource.itemIdentifier(for: indexPath),
              postID == entries.last(where: { $0.post != nil })?.post?.id,
              lastLoadedOlderPostID != postID
        else { return }
        lastLoadedOlderPostID = postID
        configuration?.onLoadOlderPost?(postID)
    }
}

private struct TimelineHostedFeedEntryView: View {
    let entry: TimelineFeedEntry
    let swipeSettings: TimelineSwipeSettings
    let isActionMenuPresented: Bool
    let gapDirection: TimelineGapFillDirection
    let isFetchingGap: Bool
    let onActionEvent: (TimelinePostActionEvent) -> Void
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia, Int) -> Void
    let onOpenURL: (URL) -> Void
    let onDismissActionMenu: () -> Void
    let onBackfillGap: (TimelineGap) -> Void

    @ViewBuilder
    var body: some View {
        switch entry {
        case .post(let post):
            TimelinePostRow(
                post: post,
                isActionMenuPresented: isActionMenuPresented,
                swipeSettings: swipeSettings,
                onActionEvent: onActionEvent,
                onOpenPost: onOpenPost,
                onOpenProfile: onOpenProfile,
                onReplyPost: onReplyPost,
                onOpenMedia: onOpenMedia,
                onOpenURL: onOpenURL,
                onDismissActionMenu: onDismissActionMenu
            )
        case .gap(let gap):
            TimelineGapRow(
                gap: isFetchingGap ? gap.replacingState(.fetching) : gap,
                direction: gapDirection,
                onTap: { onBackfillGap(gap) }
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        case .deleted(let deletedEntry):
            TimelineDeletedRow(entry: deletedEntry)
        }
    }
}

private extension UIView {
    func descendant(accessibilityIdentifier: String) -> UIView? {
        if self.accessibilityIdentifier == accessibilityIdentifier {
            return self
        }
        for subview in subviews {
            if let match = subview.descendant(
                accessibilityIdentifier: accessibilityIdentifier
            ) {
                return match
            }
        }
        return nil
    }
}
