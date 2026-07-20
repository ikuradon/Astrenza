import AstrenzaCore

@MainActor
protocol HomeTimelinePublishHandling: AnyObject {
    @discardableResult
    func enqueue(
        _ request: HomeTimelinePublishRequest,
        signer: any NostrEventSigning,
        effects: HomeTimelinePublishEffects
    ) async throws -> Bool
}

extension HomeTimelinePublishWorkflow: HomeTimelinePublishHandling {}

struct HomeTimelinePublishInteractionState: Equatable, Sendable {
    let account: NostrAccount
    let accountWriteRelays: [String]
    let fallbackRelays: [String]
}

enum HomeTimelinePublishStoreAction: Equatable, Sendable {
    case applyContentSnapshot(HomeTimelineContentSnapshot)
    case reloadNewestProjectionWindow(NostrAccount)
    case materializeEntries
    case setPhase(NostrHomeTimelinePhase)
}

enum HomeTimelinePublishAsyncAction: Equatable, Sendable {
    case persistDatabase(NostrAccount)
}

struct HomeTimelinePublishEnvironment: Sendable {
    typealias AccountIDProvider = @MainActor @Sendable () -> String?

    let currentAccountID: AccountIDProvider
}

struct HomeTimelinePublishInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelinePublishStoreAction
    ) -> Void
    typealias AsyncApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelinePublishAsyncAction
    ) async -> Void

    let environment: HomeTimelinePublishEnvironment
    let apply: ApplicationEffect
    let perform: AsyncApplicationEffect
}

struct HomeTimelinePublishInteractionContext: Sendable {
    let state: HomeTimelinePublishInteractionState
    let effects: HomeTimelinePublishInteractionEffects
}

@MainActor
final class HomeTimelinePublishInteractionWorkflow {
    private let publish: any HomeTimelinePublishHandling

    init(publish: any HomeTimelinePublishHandling) {
        self.publish = publish
    }

    @discardableResult
    func enqueue(
        input: NostrPublishInput,
        taggedUserReadRelays: [String] = [],
        signer: any NostrEventSigning,
        context: HomeTimelinePublishInteractionContext,
        reportProgress: @escaping @MainActor @Sendable (
            HomeTimelinePublishStage
        ) -> Void = { _ in }
    ) async throws -> Bool {
        try await publish.enqueue(
            HomeTimelinePublishRequest(
                input: input,
                account: context.state.account,
                accountWriteRelays: context.state.accountWriteRelays,
                taggedUserReadRelays: taggedUserReadRelays,
                fallbackRelays: context.state.fallbackRelays
            ),
            signer: signer,
            effects: publishEffects(
                for: context.effects,
                reportProgress: reportProgress
            )
        )
    }

    private func publishEffects(
        for effects: HomeTimelinePublishInteractionEffects,
        reportProgress: @escaping @MainActor @Sendable (
            HomeTimelinePublishStage
        ) -> Void
    ) -> HomeTimelinePublishEffects {
        HomeTimelinePublishEffects(
            currentAccountID: effects.environment.currentAccountID,
            applyContentSnapshot: { snapshot in
                effects.apply(.applyContentSnapshot(snapshot))
            },
            reloadNewestProjectionWindow: { account in
                effects.apply(.reloadNewestProjectionWindow(account))
            },
            materializeEntries: {
                effects.apply(.materializeEntries)
            },
            persistDatabase: { account in
                await effects.perform(.persistDatabase(account))
            },
            setPhase: { phase in
                effects.apply(.setPhase(phase))
            },
            reportProgress: reportProgress
        )
    }
}
