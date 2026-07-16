import AstrenzaCore

@MainActor
struct HomeStoreComposition {
    private struct Shared {
        let query: HomeStoreQueryCoordinator
        let projection: HomeStoreProjectionCoordinator
        let context: HomeStoreContextCoordinator
        let runtime: HomeStoreRuntimeCoordinator
        let viewport: HomeStoreViewportCoordinator
        let presentation: HomeStorePresentationCoordinator
        let status: HomeStoreStatusCoordinator

        var restoreCollaborators: HomeStoreRestoreCollaborators {
            HomeStoreRestoreCollaborators(
                viewport: viewport,
                projection: projection,
                presentation: presentation,
                runtime: runtime,
                status: status
            )
        }

        func applicationCollaborators(
            publishedState: HomeTimelinePublishedStateCoordinator,
            lifecycle: HomeStoreLifecycleCoordinator,
            sync: HomeStoreSyncCoordinator,
            state: HomeStoreStateCoordinator,
            restore: HomeStoreRestoreCoordinator
        ) -> HomeStoreApplicationCollaborators {
            HomeStoreApplicationCollaborators(
                publishedState: publishedState,
                context: context,
                query: query,
                projection: projection,
                lifecycle: lifecycle,
                sync: sync,
                state: state,
                runtime: runtime,
                viewport: viewport,
                presentation: presentation,
                status: status,
                restore: restore
            )
        }
    }

    let query: HomeStoreQueryCoordinator
    let projection: HomeStoreProjectionCoordinator
    let context: HomeStoreContextCoordinator
    let lifecycle: HomeStoreLifecycleCoordinator
    let syncPolicy: HomeStoreSyncPolicyCoordinator
    let featureActions: HomeStoreFeatureActionCoordinator
    let sync: HomeStoreSyncCoordinator
    let state: HomeStoreStateCoordinator
    let runtime: HomeStoreRuntimeCoordinator
    let viewport: HomeStoreViewportCoordinator
    let presentation: HomeStorePresentationCoordinator
    let status: HomeStoreStatusCoordinator
    let restore: HomeStoreRestoreCoordinator
    let application: HomeStoreApplicationCoordinator

    static func make(
        components: HomeTimelineStoreComponents
    ) -> HomeStoreComposition {
        let shared = makeShared(components: components)
        let lifecycle = HomeStoreLifecycleCoordinator.live(
            components: components,
            projection: shared.projection,
            contexts: shared.context
        )
        let featureActions = HomeStoreFeatureActionCoordinator.live(
            components: components,
            contexts: shared.context
        )
        let syncPolicy = HomeStoreSyncPolicyCoordinator(
            source: components.publishedStateCoordinator,
            lifecycle: lifecycle,
            settingsStore: components.syncPolicySettingsStore
        )
        let sync = HomeStoreSyncCoordinator.live(
            components: components,
            contexts: shared.context
        )
        let state = HomeStoreStateCoordinator.live(
            components: components,
            contexts: shared.context
        )
        let restore = HomeStoreRestoreCoordinator.live(
            publishedState: components.publishedStateCoordinator,
            collaborators: shared.restoreCollaborators
        )
        let application = HomeStoreApplicationCoordinator(
            collaborators: shared.applicationCollaborators(
                publishedState: components.publishedStateCoordinator,
                lifecycle: lifecycle,
                sync: sync,
                state: state,
                restore: restore
            )
        )
        shared.context.bind(
            applications: application.contextApplications
        )
        return HomeStoreComposition(
            query: shared.query,
            projection: shared.projection,
            context: shared.context,
            lifecycle: lifecycle,
            syncPolicy: syncPolicy,
            featureActions: featureActions,
            sync: sync,
            state: state,
            runtime: shared.runtime,
            viewport: shared.viewport,
            presentation: shared.presentation,
            status: shared.status,
            restore: restore,
            application: application
        )
    }

    private static func makeShared(
        components: HomeTimelineStoreComponents
    ) -> Shared {
        let query = HomeStoreQueryCoordinator.live(components: components)
        let projectionViewport = HomeProjectionViewportCoordinator()
        let context = HomeStoreContextCoordinator.live(
            components: components,
            query: query,
            projectionViewport: projectionViewport,
            hasRelayRuntime: components.relayRuntime != nil
        )
        let projection = HomeStoreProjectionCoordinator.live(
            components: components
        )
        let runtime = HomeStoreRuntimeCoordinator.live(
            components: components,
            contexts: context
        )
        let viewport = HomeStoreViewportCoordinator.live(
            components: components,
            projection: projectionViewport,
            contexts: context
        )
        let presentation = HomeStorePresentationCoordinator.live(
            components: components
        )
        let status = HomeStoreStatusCoordinator.live(
            components: components
        )
        return Shared(
            query: query,
            projection: projection,
            context: context,
            runtime: runtime,
            viewport: viewport,
            presentation: presentation,
            status: status
        )
    }
}
