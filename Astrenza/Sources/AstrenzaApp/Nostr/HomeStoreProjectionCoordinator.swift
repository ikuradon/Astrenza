import AstrenzaCore

struct HomeStoreProjectionPreparation: Sendable {
    let followedPubkeys: [String]
    let liveEvents: [NostrEvent]
}

@MainActor
protocol HomeStoreProjectionSourcing: AnyObject {
    func projectionPreparation() -> HomeStoreProjectionPreparation
}

@MainActor
final class HomeStoreProjectionSource: HomeStoreProjectionSourcing {
    private let publishedState: HomeTimelinePublishedStateCoordinator
    private let dataInteraction: HomeTimelineDataInteractionWorkflow

    init(
        publishedState: HomeTimelinePublishedStateCoordinator,
        dataInteraction: HomeTimelineDataInteractionWorkflow
    ) {
        self.publishedState = publishedState
        self.dataInteraction = dataInteraction
    }

    func projectionPreparation() -> HomeStoreProjectionPreparation {
        HomeStoreProjectionPreparation(
            followedPubkeys: publishedState.content.followedPubkeys,
            liveEvents: dataInteraction.contentState.noteEvents
        )
    }
}

@MainActor
protocol HomeStoreProjectionInteracting: AnyObject {
    func prepareDefinition(
        account: NostrAccount,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    )
    func restoredViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState?
    func reloadNewestProjection(
        account: NostrAccount,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    )
    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    )
    func cancelMaterialization()

    #if DEBUG
    func mergedWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String
    ) -> NostrFeedWindow
    func activateStoredProjection(
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    ) async
    #endif
}

extension HomeProjectionInteractionWorkflow: HomeStoreProjectionInteracting {}

@MainActor
final class HomeStoreProjectionCoordinator {
    private let source: any HomeStoreProjectionSourcing
    private let interaction: any HomeStoreProjectionInteracting

    init(
        source: any HomeStoreProjectionSourcing,
        interaction: any HomeStoreProjectionInteracting
    ) {
        self.source = source
        self.interaction = interaction
    }

    static func live(
        components: HomeTimelineStoreComponents
    ) -> HomeStoreProjectionCoordinator {
        HomeStoreProjectionCoordinator(
            source: HomeStoreProjectionSource(
                publishedState: components.publishedStateCoordinator,
                dataInteraction: components.dataInteractionWorkflow
            ),
            interaction: components.projectionInteractionWorkflow
        )
    }

    func prepareDefinition(account: NostrAccount) {
        let preparation = source.projectionPreparation()
        interaction.prepareDefinition(
            account: account,
            followedPubkeys: preparation.followedPubkeys,
            liveEvents: preparation.liveEvents
        )
    }

    func restoredViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        interaction.restoredViewportState(
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    func reloadNewestProjection(
        account: NostrAccount,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler? = nil
    ) {
        interaction.reloadNewestProjection(
            account: account,
            onCompletion: onCompletion
        )
    }

    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler? = nil
    ) {
        interaction.reloadProjection(
            account: account,
            around: anchorEventID,
            mergingWithCurrentWindow: mergingWithCurrentWindow,
            onCompletion: onCompletion
        )
    }

    func cancelMaterialization() {
        interaction.cancelMaterialization()
    }
}

#if DEBUG
extension HomeStoreProjectionCoordinator {
    func mergedWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String
    ) -> NostrFeedWindow {
        interaction.mergedWindow(
            current,
            with: loaded,
            centeredOn: anchorEventID
        )
    }

    func activateStoredProjection(
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    ) async {
        await interaction.activateStoredProjection(
            definition: definition,
            sourceAuthors: sourceAuthors
        )
    }
}
#endif
