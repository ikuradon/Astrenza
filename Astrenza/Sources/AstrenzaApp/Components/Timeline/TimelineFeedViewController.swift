import OSLog
import SwiftUI
import UIKit

@MainActor
final class TimelineFeedViewController: UIViewController {
    private static let logger = Logger(
        subsystem: "com.ikuradon.Astrenza",
        category: "TimelineFeed"
    )

    private enum Section: Hashable {
        case main
    }

    private enum ItemID: Hashable {
        case leadingContent
        case entry(TimelineFeedEntry.ID)

        var entryID: TimelineFeedEntry.ID? {
            guard case .entry(let entryID) = self else { return nil }
            return entryID
        }
    }

    private struct RowMeasurementKey: Hashable {
        let reuseKey: RowMeasurementReuseKey
        let widthInPixels: Int
        let contentSizeCategory: String
        let localeIdentifier: String
    }

    private struct EntriesApplication {
        let entries: [TimelineFeedEntry]
        let forceSnapshotApplication: Bool
        let forceVisibleReconfiguration: Bool
        let reconfigureAllVisible: Bool
        let forceLeadingReconfiguration: Bool
        let forceGeometryProjection: Bool

        func merging(_ newer: EntriesApplication) -> EntriesApplication {
            EntriesApplication(
                entries: newer.entries,
                forceSnapshotApplication:
                    forceSnapshotApplication ||
                    newer.forceSnapshotApplication,
                forceVisibleReconfiguration:
                    forceVisibleReconfiguration ||
                    newer.forceVisibleReconfiguration,
                reconfigureAllVisible:
                    reconfigureAllVisible ||
                    newer.reconfigureAllVisible,
                forceLeadingReconfiguration:
                    forceLeadingReconfiguration ||
                    newer.forceLeadingReconfiguration,
                forceGeometryProjection:
                    forceGeometryProjection ||
                    newer.forceGeometryProjection
            )
        }
    }

    private enum RowMeasurementReuseKey: Hashable {
        case simplePost(bodyTextHeightInPixels: Int)
        case exact(TimelineFeedCellSizingIdentity)
    }

    private let anchorLineY: CGFloat = 72
    private let readLineY: CGFloat = 96
    private let pullRefreshTriggerOffset: CGFloat = -96
    private let viewportSaveInterval: TimeInterval = 0.25
    private let viewportSaveOffsetThreshold: CGFloat = 48
    private static let cellReuseIdentifier = "timeline-entry"
    private let leadingContentSizingID = "\0timeline-leading-content"

    private var configuration: TimelineFeedCollectionConfiguration?
    private var entries: [TimelineFeedEntry] = []
    private var entriesByID: [TimelineFeedEntry.ID: TimelineFeedEntry] = [:]
    private var cellPayloadStore = TimelineFeedCellPayloadStore()
    private var isLeadingContentPresented = false
    private var postOrderByID: [TimelinePost.ID: Int] = [:]
    private var readLinePositionByPostID:
        [TimelinePost.ID: TimelinePostReadLinePosition] = [:]
    private var restoreCoordinator = TimelineFeedViewportRestoreCoordinator()
    private var pendingEntriesApplication: EntriesApplication?
    private var refreshAnchorTransaction =
        TimelineFeedRefreshAnchorTransaction()
    private var fetchingGapDirections:
        [TimelineGap.ID: TimelineGapFillDirection] = [:]
    private var lastScrollCommandID: UUID?
    private var lastSwipeSettings: TimelineSwipeSettings?
    private var initialViewportReadySourceIdentity: String?
    private var lastUnreadPillPlacement = HomeUnreadPillPlacement.hidden
    private var lastLoadedOlderPostID: TimelinePost.ID?
    private var lastSavedViewportAnchor: TimelineFeedVisibleAnchor?
    private var lastSavedViewportOffset: CGFloat = 0
    private var lastViewportObservation: TimelineFeedViewportObservation?
    private var presentedSourceRevision: Int?
    private var lastViewportSaveTime: TimeInterval = 0
    private var hasUserInteraction = false
    private var isApplyingSnapshot = false
    private var isProgrammaticScroll = false
    private var isUserScrollActive = false
    private var viewportInteractionGeneration: UInt64 = 0
    private var isPullRefreshArmed = false
    private var isPullRefreshing = false
    private var pullRefreshProgress: CGFloat = 0
    private var pullRefreshCompletionResult: Bool?
    private var pullRefreshTask: Task<Void, Never>?
    private var pullRefreshFeedbackTask: Task<Void, Never>?
    private var restoreRetryGeneration: UInt64 = 0
    private var missingRestoreAnchorAttempts = 0
    private var measuredRowHeights: [RowMeasurementKey: CGFloat] = [:]
    private var projectedRowHeights:
        [TimelineFeedEntry.ID: CGFloat] = [:]
    private var projectedSizingIdentities:
        [TimelineFeedEntry.ID: TimelineFeedCellSizingIdentity] = [:]
    private var projectedWidth: CGFloat = 0
    private var hasDeferredGeometryProjection = false

    private lazy var collectionLayout = TimelineFeedStableLayout()
    private lazy var rowGestureArbitrator = timelineRowGestureArbitrator(
        for: collectionView
    )
    private lazy var measurementCell = TimelineFeedHostingCollectionCell(
        frame: .zero
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
        collectionView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: TimelineFeedCollectionMetrics.home.bottomContentPadding,
            right: 0
        )
        collectionView.verticalScrollIndicatorInsets =
            collectionView.contentInset
        collectionView.keyboardDismissMode = .interactive
        collectionView.accessibilityIdentifier = "timeline.feed"
        collectionView.register(
            TimelineFeedHostingCollectionCell.self,
            forCellWithReuseIdentifier: Self.cellReuseIdentifier
        )
        collectionView.delegate = self
        return collectionView
    }()

    private lazy var dataSource = makeDataSource()

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
        reprojectForCurrentWidthIfNeeded()
        attemptPendingRestoreIfPossible()
        publishInitialViewportReadyIfPossible()
        publishUnreadPillPlacement()
        publishViewportObservation()
    }

    private func applyMetrics(_ metrics: TimelineFeedCollectionMetrics) {
        guard abs(
            collectionView.contentInset.bottom - metrics.bottomContentPadding
        ) > 0.5 else { return }
        collectionView.contentInset.bottom = metrics.bottomContentPadding
        collectionView.verticalScrollIndicatorInsets =
            collectionView.contentInset
    }

    func apply(_ nextConfiguration: TimelineFeedCollectionConfiguration) {
        loadViewIfNeeded()
        let previousConfiguration = configuration
        let sourceChanged = previousConfiguration?.sourceIdentity !=
            nextConfiguration.sourceIdentity
        configuration = nextConfiguration
        applyMetrics(nextConfiguration.metrics)

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
        let swipeSettingsChanged = lastSwipeSettings !=
            nextConfiguration.swipeSettings
        let contentRevisionChanged = previousConfiguration?.sourceRevision !=
            nextConfiguration.sourceRevision
        let previousLeadingContent = previousConfiguration?.leadingContent
        let nextLeadingContent = nextConfiguration.leadingContent
        let leadingRenderChanged = previousLeadingContent?.renderRevision !=
            nextLeadingContent?.renderRevision
        let leadingGeometryChanged = previousLeadingContent?.geometryRevision !=
            nextLeadingContent?.geometryRevision
        let metricsChanged = previousConfiguration?.metrics !=
            nextConfiguration.metrics
        lastSwipeSettings = nextConfiguration.swipeSettings
        if sourceChanged ||
            contentRevisionChanged ||
            swipeSettingsChanged ||
            leadingRenderChanged ||
            leadingGeometryChanged ||
            metricsChanged {
            applyEntries(
                nextConfiguration.entries,
                forceSnapshotApplication: sourceChanged,
                forceVisibleReconfiguration:
                    contentRevisionChanged || swipeSettingsChanged,
                reconfigureAllVisible: swipeSettingsChanged,
                forceLeadingReconfiguration:
                    leadingRenderChanged || leadingGeometryChanged,
                forceGeometryProjection:
                    leadingGeometryChanged || metricsChanged
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
        saveViewportStateIfPossible(force: true)
        pendingEntriesApplication = nil
        setUserScrollActive(false)
        resetPullRefreshPresentation()
    }

    private func makeDataSource()
        -> UICollectionViewDiffableDataSource<
            Section,
            ItemID
        > {
        UICollectionViewDiffableDataSource(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, itemID in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: Self.cellReuseIdentifier,
                for: indexPath
            ) as! TimelineFeedHostingCollectionCell
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            guard let self, let configuration else {
                Self.configureUnavailableCell(
                    cell,
                    itemID: itemID,
                    projectedHeight: collectionView.collectionViewLayout
                        .layoutAttributesForItem(at: indexPath)?.size.height,
                    parentViewController: self
                )
                return cell
            }
            if itemID == .leadingContent,
               let leadingContent = cellPayloadStore.leadingContent {
                let sizingIdentity = leadingContentSizingIdentity(
                    leadingContent,
                    configuration: configuration
                )
                cell.configure(
                    rootView: leadingContent.rootView,
                    parentViewController: self,
                    sizingIdentity: sizingIdentity
                )
                return cell
            }

            guard case .entry(let entryID) = itemID,
                  let entry = cellPayloadStore.entry(for: entryID)
            else {
                Self.logger.fault(
                    "Missing payload for diffable item \(String(describing: itemID), privacy: .public)"
                )
                Self.configureUnavailableCell(
                    cell,
                    itemID: itemID,
                    projectedHeight: collectionView.collectionViewLayout
                        .layoutAttributesForItem(at: indexPath)?.size.height,
                    parentViewController: self
                )
                return cell
            }
            let sizingIdentity = rowSizingIdentity(
                for: entry,
                configuration: configuration
            )
            let hostedView = hostedContentView(
                for: entry,
                configuration: configuration,
                sizingIdentity: sizingIdentity
            )
            cell.configure(
                rootView: hostedView,
                parentViewController: self,
                sizingIdentity: sizingIdentity
            )
            return cell
        }
    }

    private static func configureUnavailableCell(
        _ cell: TimelineFeedHostingCollectionCell,
        itemID: ItemID,
        projectedHeight: CGFloat?,
        parentViewController: UIViewController?
    ) {
        let height = max(1, projectedHeight ?? 1)
        cell.configure(
            rootView: AnyView(
                Color.clear
                    .frame(height: height)
                    .fixedSize(horizontal: false, vertical: true)
            ),
            parentViewController: parentViewController,
            sizingIdentity: TimelineFeedCellSizingIdentity(
                entryID: "unavailable-\(String(describing: itemID))",
                geometryFingerprint: height.hashValue,
                swipeSettings: TimelineSwipeSettings(),
                gapDirection: .older,
                isFetchingGap: false
            )
        )
    }

    private func leadingContentSizingIdentity(
        _ leadingContent: TimelineFeedLeadingContent,
        configuration: TimelineFeedCollectionConfiguration
    ) -> TimelineFeedCellSizingIdentity {
        TimelineFeedCellSizingIdentity(
            entryID: leadingContentSizingID,
            geometryFingerprint: leadingContent.geometryRevision,
            swipeSettings: configuration.swipeSettings,
            gapDirection: .older,
            isFetchingGap: false
        )
    }

    private func rowSizingIdentity(
        for entry: TimelineFeedEntry,
        configuration: TimelineFeedCollectionConfiguration
    ) -> TimelineFeedCellSizingIdentity {
        let gapDirection: TimelineGapFillDirection
        switch entry {
        case .gap:
            gapDirection = displayGapDirection(for: entry.id)
        case .post, .deleted:
            gapDirection = .older
        }
        return TimelineFeedCellSizingIdentity(
            entryID: entry.id,
            geometryFingerprint: TimelineGeometryFingerprint.entry(entry),
            swipeSettings: configuration.swipeSettings,
            gapDirection: gapDirection,
            isFetchingGap: fetchingGapDirections[entry.id] != nil
        )
    }

    private func hostedContentView(
        for entry: TimelineFeedEntry,
        configuration: TimelineFeedCollectionConfiguration,
        sizingIdentity: TimelineFeedCellSizingIdentity
    ) -> AnyView {
        AnyView(
            TimelineHostedFeedEntryView(
                entry: entry,
                swipeSettings: configuration.swipeSettings,
                gapDirection: sizingIdentity.gapDirection,
                isFetchingGap: sizingIdentity.isFetchingGap,
                onOpenPost: { [weak self] post in
                    self?.openPost(post)
                },
                onRowTap: { [weak self] post in
                    self?.openPostFromRowTap(post)
                },
                onOpenProfile: configuration.onOpenProfile,
                onReplyPost: configuration.onReplyPost,
                onOpenMedia: configuration.onOpenMedia,
                onOpenURL: configuration.onOpenURL,
                onPostActionChoice: configuration.onPostActionChoice,
                onBackfillGap: { [weak self] gap in
                    self?.requestBackfill(gap)
                }
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .id(sizingIdentity)
            .background(Color.astrenzaBackground)
        )
    }

    private func configureProjectedGeometry(
        for projectedEntries: [TimelineFeedEntry],
        configuration: TimelineFeedCollectionConfiguration,
        width: CGFloat,
        freezesExistingRows: Bool
    ) {
        guard width > 0 else { return }
        let displayScale = max(
            1,
            collectionView.traitCollection.displayScale
        )
        measurementCell.traitOverrides.preferredContentSizeCategory =
            collectionView.traitCollection.preferredContentSizeCategory
        measurementCell.traitOverrides.layoutDirection =
            collectionView.traitCollection.layoutDirection
        measurementCell.traitOverrides.displayScale = displayScale
        let widthInPixels = Int((width * displayScale).rounded())
        let contentSizeCategory = collectionView
            .traitCollection
            .preferredContentSizeCategory
            .rawValue
        let localeIdentifier = Locale.autoupdatingCurrent.identifier
        var nextHeights: [TimelineFeedEntry.ID: CGFloat] = [:]
        var nextIdentities:
            [TimelineFeedEntry.ID: TimelineFeedCellSizingIdentity] = [:]
        var items: [TimelineFeedProjectedLayoutItem] = []
        let projectedItemCount = projectedEntries.count +
            (configuration.leadingContent == nil ? 0 : 1)
        nextHeights.reserveCapacity(projectedItemCount)
        nextIdentities.reserveCapacity(projectedItemCount)
        items.reserveCapacity(projectedItemCount)

        if let leadingContent = configuration.leadingContent {
            let sizingIdentity = leadingContentSizingIdentity(
                leadingContent,
                configuration: configuration
            )
            let height: CGFloat
            if freezesExistingRows,
               let projectedHeight = projectedRowHeights[
                   leadingContentSizingID
               ] {
                height = projectedHeight
                if projectedSizingIdentities[leadingContentSizingID] !=
                    sizingIdentity {
                    hasDeferredGeometryProjection = true
                }
            } else {
                let measurementKey = RowMeasurementKey(
                    reuseKey: .exact(sizingIdentity),
                    widthInPixels: widthInPixels,
                    contentSizeCategory: contentSizeCategory,
                    localeIdentifier: localeIdentifier
                )
                if let measuredHeight = measuredRowHeights[measurementKey] {
                    height = measuredHeight
                } else {
                    measurementCell.configure(
                        rootView: leadingContent.rootView,
                        parentViewController: nil,
                        sizingIdentity: sizingIdentity
                    )
                    height = measurementCell.measuredHeight(
                        fittingWidth: width
                    )
                    measuredRowHeights[measurementKey] = height
                }
            }
            nextHeights[leadingContentSizingID] = height
            nextIdentities[leadingContentSizingID] = sizingIdentity
            items.append(
                TimelineFeedProjectedLayoutItem(
                    id: leadingContentSizingID,
                    height: height
                )
            )
        }

        for entry in projectedEntries {
            let sizingIdentity = rowSizingIdentity(
                for: entry,
                configuration: configuration
            )
            let height: CGFloat
            if freezesExistingRows,
               let projectedHeight = projectedRowHeights[entry.id] {
                height = projectedHeight
                if projectedSizingIdentities[entry.id] != sizingIdentity {
                    hasDeferredGeometryProjection = true
                }
            } else {
                let measurementKey = RowMeasurementKey(
                    reuseKey: rowMeasurementReuseKey(
                        for: entry,
                        sizingIdentity: sizingIdentity,
                        width: width,
                        displayScale: displayScale
                    ),
                    widthInPixels: widthInPixels,
                    contentSizeCategory: contentSizeCategory,
                    localeIdentifier: localeIdentifier
                )
                if let measuredHeight = measuredRowHeights[measurementKey] {
                    height = measuredHeight
                } else {
                    let hostedView = hostedContentView(
                        for: entry,
                        configuration: configuration,
                        sizingIdentity: sizingIdentity
                    )
                    measurementCell.configure(
                        rootView: hostedView,
                        parentViewController: nil,
                        sizingIdentity: sizingIdentity
                    )
                    height = measurementCell.measuredHeight(
                        fittingWidth: width
                    )
                    measuredRowHeights[measurementKey] = height
                }
            }
            nextHeights[entry.id] = height
            nextIdentities[entry.id] = sizingIdentity
            items.append(
                TimelineFeedProjectedLayoutItem(
                    id: entry.id,
                    height: height
                )
            )
        }
        projectedWidth = width
        projectedRowHeights = nextHeights
        projectedSizingIdentities = nextIdentities
        collectionLayout.configure(
            items: items,
            topPadding: configuration.metrics.topContentPadding
        )
    }

    private func rowMeasurementReuseKey(
        for entry: TimelineFeedEntry,
        sizingIdentity: TimelineFeedCellSizingIdentity,
        width: CGFloat,
        displayScale: CGFloat
    ) -> RowMeasurementReuseKey {
        guard case .post(let post) = entry,
              post.richBody == nil,
              post.repostedBy == nil,
              post.quotedPost == nil,
              post.replyContext == nil,
              post.replyMention == nil,
              post.contentWarning == nil,
              case .standard = post.bodyPresentation,
              post.linkSummary == nil,
              post.media == nil
        else {
            return .exact(sizingIdentity)
        }
        let availableWidth = max(
            1,
            width -
                AstrenzaTimelineMetrics.rowHorizontalPadding * 2 -
                AstrenzaTimelineMetrics.avatarSize -
                AstrenzaTimelineMetrics.rowAvatarSpacing
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = AstrenzaTimelineMetrics.bodyLineSpacing
        let attributedBody = NSAttributedString(
            string: post.body,
            attributes: [
                .font: UIFont.systemFont(
                    ofSize: AstrenzaTimelineMetrics.bodyFontSize,
                    weight: .regular
                ),
                .paragraphStyle: paragraphStyle,
            ]
        )
        let bodyHeight = attributedBody.boundingRect(
            with: CGSize(
                width: availableWidth,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height
        return .simplePost(
            bodyTextHeightInPixels: Int(
                ceil(bodyHeight * displayScale)
            )
        )
    }

    private func currentProjectionWidth() -> CGFloat {
        if collectionView.bounds.width > 0 {
            return collectionView.bounds.width
        }
        if view.bounds.width > 0 {
            return view.bounds.width
        }
        return view.window?.screen.bounds.width ?? 390
    }

    private func reprojectForCurrentWidthIfNeeded() {
        guard (!entries.isEmpty || configuration?.leadingContent != nil),
              !isApplyingSnapshot,
              let configuration
        else { return }
        let width = currentProjectionWidth()
        guard abs(width - projectedWidth) > 0.5 else { return }
        let anchor = captureVisibleAnchor()
        configureProjectedGeometry(
            for: entries,
            configuration: configuration,
            width: width,
            freezesExistingRows: false
        )
        collectionView.layoutIfNeeded()
        if let anchor {
            preserve(anchor)
        }
    }

    private func commitDeferredGeometryProjectionIfNeeded() {
        guard hasDeferredGeometryProjection,
              !isUserScrollActive,
              let configuration
        else { return }
        hasDeferredGeometryProjection = false
        let anchor = captureVisibleAnchor()
        configureProjectedGeometry(
            for: entries,
            configuration: configuration,
            width: currentProjectionWidth(),
            freezesExistingRows: false
        )
        collectionView.layoutIfNeeded()
        if let anchor {
            preserve(anchor)
        }
    }

    private func resetForSourceChange() {
        resetPullRefreshPresentation()
        restoreRetryGeneration &+= 1
        measuredRowHeights = [:]
        projectedRowHeights = [:]
        projectedSizingIdentities = [:]
        projectedWidth = 0
        hasDeferredGeometryProjection = false
        entries = []
        entriesByID = [:]
        isLeadingContentPresented = false
        postOrderByID = [:]
        readLinePositionByPostID = [:]
        pendingEntriesApplication = nil
        refreshAnchorTransaction.reset()
        fetchingGapDirections = [:]
        lastScrollCommandID = nil
        initialViewportReadySourceIdentity = nil
        lastUnreadPillPlacement = .hidden
        lastLoadedOlderPostID = nil
        lastSavedViewportAnchor = nil
        lastSavedViewportOffset = 0
        lastViewportObservation = nil
        presentedSourceRevision = nil
        lastViewportSaveTime = 0
        hasUserInteraction = false
        isProgrammaticScroll = true
        collectionView.setContentOffset(.zero, animated: false)
        isProgrammaticScroll = false
    }

    private func applyEntries(
        _ newEntries: [TimelineFeedEntry],
        forceSnapshotApplication: Bool = false,
        forceVisibleReconfiguration: Bool,
        reconfigureAllVisible: Bool = false,
        forceLeadingReconfiguration: Bool = false,
        forceGeometryProjection: Bool = false
    ) {
        let application = EntriesApplication(
            entries: newEntries,
            forceSnapshotApplication: forceSnapshotApplication,
            forceVisibleReconfiguration: forceVisibleReconfiguration,
            reconfigureAllVisible: reconfigureAllVisible,
            forceLeadingReconfiguration: forceLeadingReconfiguration,
            forceGeometryProjection: forceGeometryProjection
        )
        guard !isApplyingSnapshot, !isUserScrollActive else {
            pendingEntriesApplication = pendingEntriesApplication?
                .merging(application) ?? application
            return
        }
        applyEntries(application)
    }

    @discardableResult
    private func applyEntries(
        _ application: EntriesApplication
    ) -> Bool {
        let newEntries = application.entries
        let oldIDs = entries.map(\.id)
        let newIDs = newEntries.map(\.id)
        let presentsLeadingContent = configuration?.leadingContent != nil
        let leadingStructureChanged = isLeadingContentPresented !=
            presentsLeadingContent
        let structureChanged = oldIDs != newIDs || leadingStructureChanged
        cellPayloadStore.stage(
            entries: newEntries,
            leadingContent: configuration?.leadingContent
        )
        guard application.forceSnapshotApplication ||
                structureChanged ||
                application.forceVisibleReconfiguration ||
                application.forceLeadingReconfiguration ||
                application.forceGeometryProjection
        else {
            entries = newEntries
            entriesByID = Dictionary(
                uniqueKeysWithValues: newEntries.map { ($0.id, $0) }
            )
            rebuildPostOrder()
            presentedSourceRevision = configuration?.sourceRevision
            refreshAnchorTransaction.didPresent(
                sourceRevision: presentedSourceRevision
            )
            publishViewportObservation(force: true)
            return false
        }

        let oldIDSet = Set(oldIDs)
        let newIDSet = Set(newIDs)
        let visibleIDs = Set(
            collectionView.indexPathsForVisibleItems.compactMap {
                dataSource.itemIdentifier(for: $0)?.entryID
            }
        )
        let commonVisibleIDs = visibleIDs
            .intersection(oldIDSet)
            .intersection(newIDSet)
        var reconfiguredIDs: Set<TimelineFeedEntry.ID>
        if !application.forceVisibleReconfiguration {
            reconfiguredIDs = []
        } else if application.reconfigureAllVisible {
            reconfiguredIDs = commonVisibleIDs
        } else {
            let oldFingerprintsByID = Dictionary(
                uniqueKeysWithValues: entries.compactMap { entry in
                    commonVisibleIDs.contains(entry.id)
                        ? (
                            entry.id,
                            TimelineRenderFingerprint.entry(entry)
                        )
                        : nil
                }
            )
            reconfiguredIDs = Set(
                newEntries.compactMap { entry -> TimelineFeedEntry.ID? in
                    guard commonVisibleIDs.contains(entry.id),
                          let oldFingerprint =
                            oldFingerprintsByID[entry.id],
                          oldFingerprint !=
                            TimelineRenderFingerprint.entry(entry)
                    else { return nil }
                    return entry.id
                }
            )
        }

        let visibleAnchor = captureVisibleAnchor()
        let plannedInteractionGeneration = viewportInteractionGeneration
        let postSnapshotPosition = TimelineFeedViewportMutationPlanner
            .position(
                for: TimelineFeedViewportMutationInput(
                    oldIDs: oldIDs,
                    newIDs: newIDs,
                    visibleAnchor: visibleAnchor,
                    refreshAnchor: refreshAnchorTransaction.anchor,
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
        isLeadingContentPresented = presentsLeadingContent
        entriesByID = Dictionary(
            uniqueKeysWithValues: newEntries.map { ($0.id, $0) }
        )
        rebuildPostOrder()
        fetchingGapDirections = fetchingGapDirections.filter {
            entriesByID[$0.key] != nil
        }
        if let configuration {
            configureProjectedGeometry(
                for: newEntries,
                configuration: configuration,
                width: currentProjectionWidth(),
                freezesExistingRows: isUserScrollActive
            )
        }
        var snapshot = NSDiffableDataSourceSnapshot<
            Section,
            ItemID
        >()
        snapshot.appendSections([.main])
        let entryItemIDs = newIDs.map(ItemID.entry)
        let collectionItemIDs = presentsLeadingContent
            ? [.leadingContent] + entryItemIDs
            : entryItemIDs
        snapshot.appendItems(collectionItemIDs, toSection: .main)
        if application.forceLeadingReconfiguration &&
            presentsLeadingContent {
            snapshot.reconfigureItems([.leadingContent])
        }
        if !reconfiguredIDs.isEmpty {
            snapshot.reconfigureItems(
                reconfiguredIDs.map(ItemID.entry)
            )
        }

        let appliedSourceIdentity = configuration?.sourceIdentity
        let appliedSourceRevision = configuration?.sourceRevision
        isApplyingSnapshot = true
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            retainCellPayloadsForCurrentSnapshot()
            view.layoutIfNeeded()
            if configuration?.sourceIdentity == appliedSourceIdentity {
                applyPostSnapshotPosition(
                    postSnapshotPosition,
                    plannedInteractionGeneration:
                        plannedInteractionGeneration
                )
                presentedSourceRevision = appliedSourceRevision
            }
            isApplyingSnapshot = false
            refreshAnchorTransaction.didPresent(
                sourceRevision: presentedSourceRevision
            )
            publishViewportObservation(force: true)
            if applyPendingEntriesIfPossible() {
                return
            }
            attemptPendingRestoreIfPossible()
            publishInitialViewportReadyIfPossible()
            updateReadLinePositions()
            publishUnreadPillPlacement(force: true)
        }
        return true
    }

    private func retainCellPayloadsForCurrentSnapshot() {
        let itemIDs = dataSource.snapshot().itemIdentifiers
        cellPayloadStore.retainPayloads(
            for: Set(itemIDs.compactMap(\.entryID)),
            presentsLeadingContent: itemIDs.contains(.leadingContent)
        )
    }

    private func applyPostSnapshotPosition(
        _ plannedPosition: TimelineFeedSnapshotPosition,
        plannedInteractionGeneration: UInt64
    ) {
        let position = TimelineFeedSnapshotPositionCommitPlanner.position(
            for: TimelineFeedSnapshotPositionCommitInput(
                plannedPosition: plannedPosition,
                followsRealtimeEntries:
                    configuration?.followsRealtimeEntries == true,
                isUserInteractionActive:
                    viewportInteractionGeneration !=
                    plannedInteractionGeneration ||
                    isUserScrollActive ||
                    collectionView.isTracking ||
                    collectionView.isDragging ||
                    collectionView.isDecelerating,
                isPullRefreshProtected:
                    refreshAnchorTransaction.isProtected ||
                    isPullRefreshing,
                isRestoreProtected:
                    configuration?.viewportRestoreProtectionActive == true,
                isRestoreBlocked: restoreCoordinator.blocksPersistence
            )
        )
        switch position {
        case .unchanged:
            break
        case .preserve(let anchor):
            preserve(anchor)
        case .followNewest:
            setContentOffset(0)
        }
    }

    @discardableResult
    private func applyPendingEntriesIfPossible() -> Bool {
        guard !isApplyingSnapshot,
              !isUserScrollActive,
              let pendingEntriesApplication
        else { return false }
        self.pendingEntriesApplication = nil
        return applyEntries(pendingEntriesApplication)
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
        DispatchQueue.main.async { [weak self] in
            self?.publishViewportObservation(force: true)
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
            for: .entry(request.state.anchorPostID)
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
        guard let indexPath = dataSource.indexPath(
            for: .entry(state.anchorPostID)
        ),
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
        guard let indexPath = dataSource.indexPath(
            for: .entry(state.anchorPostID)
        ),
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
            guard let entryID = dataSource.itemIdentifier(
                for: indexPath
            )?.entryID,
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

    private func publishViewportObservation(force: Bool = false) {
        guard !isApplyingSnapshot,
              let configuration
        else { return }
        let observation = TimelineFeedViewportObservation(
            collectionHeadPostID: entries.first?.post?.id,
            visibleHeadPostID: captureVisibleAnchor()?.postID,
            isAtContentStart:
                collectionView.contentOffset.y <=
                minimumContentOffset +
                HomeTimelineViewportRestorePolicy
                    .newestWindowMaximumOffset,
            isUserScrollActive: isUserScrollActive,
            isPullRefreshing: isPullRefreshing,
            sourceRevision: presentedSourceRevision ?? 0
        )
        guard force || observation != lastViewportObservation else { return }
        lastViewportObservation = observation
        configuration.onViewportObservationChanged(observation)
    }

    private func preserve(_ anchor: TimelineFeedVisibleAnchor) {
        guard let indexPath = dataSource.indexPath(
            for: .entry(anchor.postID)
        ) else {
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
            guard let postID = dataSource.itemIdentifier(
                for: indexPath
            )?.entryID,
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
           let indexPath = dataSource.indexPath(
               for: .entry(anchorPostID)
           ),
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
            guard let postID = dataSource.itemIdentifier(
                for: indexPath
            )?.entryID,
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

    private func openPost(_ post: TimelinePost) {
        configuration?.onOpenPost(post)
    }

    private func openPostFromRowTap(_ post: TimelinePost) {
        guard !rowGestureArbitrator.suppressesRowTap else { return }
        openPost(post)
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
        guard let indexPath = dataSource.indexPath(
            for: .entry(entryID)
        ),
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
        let validIDs = entryIDs
            .map(ItemID.entry)
            .filter { currentIDs.contains($0) }
        guard !validIDs.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(validIDs)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func updatePullRefresh(offset: CGFloat) {
        guard configuration?.onRefresh != nil else { return }
        guard !isPullRefreshing else {
            publishPullRefreshPresentation()
            return
        }
        let progress = min(
            max(
                abs(min(offset, 0)) / abs(pullRefreshTriggerOffset),
                0
            ),
            1
        )
        pullRefreshProgress = progress
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
        pullRefreshFeedbackTask?.cancel()
        pullRefreshFeedbackTask = nil
        pullRefreshCompletionResult = nil
        isPullRefreshing = true
        pullRefreshProgress = 1
        let refreshAnchor = captureVisibleAnchor()
        refreshAnchorTransaction.begin(anchor: refreshAnchor)
        publishPullRefreshPresentation()
        publishViewportObservation(force: true)

        pullRefreshTask?.cancel()
        pullRefreshTask = Task { @MainActor [weak self] in
            let result = await onRefresh(refreshAnchor)
            guard let self, !Task.isCancelled else { return }
            refreshAnchorTransaction.receive(
                result,
                presentedSourceRevision: presentedSourceRevision
            )
            isPullRefreshing = false
            pullRefreshProgress = 0
            pullRefreshCompletionResult = result.didUpdate
            publishPullRefreshPresentation()
            publishViewportObservation(force: true)
            pullRefreshTask = nil
            schedulePullRefreshFeedbackDismissal()
        }
    }

    private func publishPullRefreshPresentation() {
        let presentation: TimelinePullRefreshPresentation
        if isPullRefreshing {
            presentation = .refreshing
        } else if let pullRefreshCompletionResult {
            presentation = .completed(didUpdate: pullRefreshCompletionResult)
        } else if pullRefreshProgress > 0 {
            presentation = .pulling(progress: pullRefreshProgress)
        } else {
            presentation = .idle
        }
        configuration?.onPullRefreshPresentationChanged(presentation)
    }

    private func schedulePullRefreshFeedbackDismissal() {
        pullRefreshFeedbackTask?.cancel()
        pullRefreshFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            pullRefreshCompletionResult = nil
            pullRefreshFeedbackTask = nil
            publishPullRefreshPresentation()
        }
    }

    private func clearPullRefreshCompletion() {
        guard pullRefreshCompletionResult != nil else { return }
        pullRefreshFeedbackTask?.cancel()
        pullRefreshFeedbackTask = nil
        pullRefreshCompletionResult = nil
        publishPullRefreshPresentation()
    }

    private func resetPullRefreshPresentation() {
        pullRefreshTask?.cancel()
        pullRefreshFeedbackTask?.cancel()
        pullRefreshTask = nil
        pullRefreshFeedbackTask = nil
        isPullRefreshArmed = false
        isPullRefreshing = false
        pullRefreshProgress = 0
        pullRefreshCompletionResult = nil
        refreshAnchorTransaction.reset()
        publishPullRefreshPresentation()
    }

    private func setUserScrollActive(_ isActive: Bool) {
        guard isUserScrollActive != isActive else { return }
        isUserScrollActive = isActive
        if isActive {
            viewportInteractionGeneration &+= 1
        }
        configuration?.onScrollActivityChanged(isActive)
        publishViewportObservation(force: true)
        if !isActive {
            commitDeferredGeometryProjectionIfNeeded()
            _ = applyPendingEntriesIfPossible()
        }
    }
}

extension TimelineFeedViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        defer {
            collectionView.deselectItem(at: indexPath, animated: false)
        }

        guard let entryID = dataSource.itemIdentifier(
            for: indexPath
        )?.entryID,
              case .post(let post) = entriesByID[entryID]
        else { return }

        openPostFromRowTap(post)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        hasUserInteraction = true
        clearPullRefreshCompletion()
        setUserScrollActive(true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isProgrammaticScroll,
              !restoreCoordinator.blocksPersistence,
              !isSnapshotLayoutAdjustment(scrollView)
        else { return }

        let offset = scrollView.contentOffset.y
        configuration?.onScrollOffsetChanged(offset)
        updatePullRefresh(offset: offset)
        updateReadLinePositions()
        publishUnreadPillPlacement()
        publishViewportObservation()
        saveViewportStateIfPossible()
    }

    private func isSnapshotLayoutAdjustment(
        _ scrollView: UIScrollView
    ) -> Bool {
        isApplyingSnapshot &&
            !isUserScrollActive &&
            !scrollView.isTracking &&
            !scrollView.isDragging &&
            !scrollView.isDecelerating
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
        guard let postID = dataSource.itemIdentifier(
            for: indexPath
        )?.entryID,
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
    let gapDirection: TimelineGapFillDirection
    let isFetchingGap: Bool
    let onOpenPost: (TimelinePost) -> Void
    let onRowTap: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia, Int) -> Void
    let onOpenURL: (URL) -> Void
    let onPostActionChoice: (TimelinePost, PostActionChoice) -> Void
    let onBackfillGap: (TimelineGap) -> Void

    @ViewBuilder
    var body: some View {
        switch entry {
        case .post(let post):
            TimelinePostRow(
                post: post,
                swipeSettings: swipeSettings,
                onOpenPost: onOpenPost,
                onOpenProfile: onOpenProfile,
                onReplyPost: onReplyPost,
                onOpenMedia: onOpenMedia,
                onOpenURL: onOpenURL,
                onPostActionChoice: onPostActionChoice,
                onRowTap: onRowTap
            )
        case .gap(let gap):
            TimelineGapRow(
                gap: isFetchingGap ? gap.replacingState(.fetching) : gap,
                direction: gapDirection,
                onTap: { onBackfillGap(gap) }
            )
            .padding(.horizontal, AstrenzaSpacing.point14)
            .padding(.vertical, AstrenzaSpacing.point8)
        case .deleted(let deletedEntry):
            TimelineDeletedRow(entry: deletedEntry)
        }
    }
}
