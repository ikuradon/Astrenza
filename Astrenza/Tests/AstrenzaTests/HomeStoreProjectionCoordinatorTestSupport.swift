import AstrenzaCore
import Foundation
@testable import Astrenza

@MainActor
final class StoreProjectionSourceSpy: HomeStoreProjectionSourcing {
    var preparation: HomeStoreProjectionPreparation
    private(set) var readCount = 0

    init(preparation: HomeStoreProjectionPreparation) {
        self.preparation = preparation
    }

    func projectionPreparation() -> HomeStoreProjectionPreparation {
        readCount += 1
        return preparation
    }
}

@MainActor
final class StoreProjectionInteractionSpy: HomeStoreProjectionInteracting {
    enum Call: Equatable {
        case prepare(
            accountID: String,
            followedPubkeys: [String],
            eventIDs: [String]
        )
        case restoredViewport(accountID: String, timelineKey: String)
        case reloadNewest(accountID: String)
        case reload(
            accountID: String,
            anchorEventID: String?,
            mergesCurrentWindow: Bool
        )
        case cancelMaterialization
        #if DEBUG
        case merge(
            currentEventIDs: [String],
            loadedEventIDs: [String],
            anchorEventID: String
        )
        case activate(feedID: String, sourceAuthors: [String])
        #endif
    }

    var restoredViewport: TimelineViewportState?
    var reloadNewestResult = true
    var reloadResult = false
    #if DEBUG
    var mergedWindowResult: NostrFeedWindow?
    #endif
    private(set) var calls: [Call] = []

    func prepareDefinition(
        account: NostrAccount,
        followedPubkeys: [String],
        liveEvents: [NostrEvent]
    ) {
        calls.append(.prepare(
            accountID: account.pubkey,
            followedPubkeys: followedPubkeys,
            eventIDs: liveEvents.map(\.id)
        ))
    }

    func restoredViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        calls.append(.restoredViewport(
            accountID: accountID,
            timelineKey: timelineKey
        ))
        return restoredViewport
    }

    func reloadNewestProjection(
        account: NostrAccount,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    ) {
        calls.append(.reloadNewest(accountID: account.pubkey))
        onCompletion?(reloadNewestResult)
    }

    func reloadProjection(
        account: NostrAccount,
        around anchorEventID: String?,
        mergingWithCurrentWindow: Bool,
        onCompletion: HomeTimelineMaterializationCoordinating
            .ProjectionReloadHandler?
    ) {
        calls.append(.reload(
            accountID: account.pubkey,
            anchorEventID: anchorEventID,
            mergesCurrentWindow: mergingWithCurrentWindow
        ))
        onCompletion?(reloadResult)
    }

    func cancelMaterialization() {
        calls.append(.cancelMaterialization)
    }

    #if DEBUG
    func mergedWindow(
        _ current: NostrFeedWindow,
        with loaded: NostrFeedWindow,
        centeredOn anchorEventID: String
    ) -> NostrFeedWindow {
        calls.append(.merge(
            currentEventIDs: current.events.map(\.id),
            loadedEventIDs: loaded.events.map(\.id),
            anchorEventID: anchorEventID
        ))
        return mergedWindowResult ?? current
    }

    func activateStoredProjection(
        definition: NostrFeedDefinitionRecord,
        sourceAuthors: [String]
    ) async {
        calls.append(.activate(
            feedID: definition.feedID,
            sourceAuthors: sourceAuthors
        ))
    }
    #endif
}

@MainActor
struct StoreProjectionCoordinatorFixture {
    let account: NostrAccount
    let firstEvent: NostrEvent
    let secondEvent: NostrEvent
    let definition: NostrFeedDefinitionRecord
    let currentWindow: NostrFeedWindow
    let loadedWindow: NostrFeedWindow
    let source: StoreProjectionSourceSpy
    let interaction: StoreProjectionInteractionSpy
    let coordinator: HomeStoreProjectionCoordinator

    init() {
        let accountID = String(repeating: "a", count: 64)
        let account = Self.account(accountID: accountID)
        let firstEvent = Self.event(idCharacter: "1", accountID: accountID)
        let secondEvent = Self.event(idCharacter: "2", accountID: accountID)
        let definition = Self.definition(accountID: accountID)
        let currentWindow = Self.window(
            definition: definition,
            events: [firstEvent]
        )
        let loadedWindow = Self.window(
            definition: definition,
            events: [secondEvent]
        )
        let source = StoreProjectionSourceSpy(
            preparation: HomeStoreProjectionPreparation(
                followedPubkeys: [accountID],
                liveEvents: [firstEvent]
            )
        )
        let interaction = StoreProjectionInteractionSpy()
        interaction.restoredViewport = TimelineViewportState(
            accountID: accountID,
            timelineKey: "home",
            anchorPostID: "anchor",
            anchorOffset: 12,
            contentOffset: 120,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        #if DEBUG
        interaction.mergedWindowResult = loadedWindow
        #endif
        self.account = account
        self.firstEvent = firstEvent
        self.secondEvent = secondEvent
        self.definition = definition
        self.currentWindow = currentWindow
        self.loadedWindow = loadedWindow
        self.source = source
        self.interaction = interaction
        coordinator = HomeStoreProjectionCoordinator(
            source: source,
            interaction: interaction
        )
    }

    private static func account(accountID: String) -> NostrAccount {
        NostrAccount(
            pubkey: accountID,
            displayIdentifier: "store-projection",
            readOnly: true
        )
    }

    private static func definition(
        accountID: String
    ) -> NostrFeedDefinitionRecord {
        NostrFeedDefinitionRecord(
            feedID: "home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(),
            specificationHash: "store-projection",
            revision: 1,
            createdAt: 1,
            updatedAt: 1
        )
    }

    private static func event(
        idCharacter: Character,
        accountID: String
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: idCharacter, count: 64),
            pubkey: accountID,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "store projection",
            sig: String(repeating: "0", count: 128)
        )
    }

    private static func window(
        definition: NostrFeedDefinitionRecord,
        events: [NostrEvent]
    ) -> NostrFeedWindow {
        NostrFeedWindow(
            definition: definition,
            memberships: [],
            events: events,
            deletedItems: [],
            gaps: []
        )
    }
}
