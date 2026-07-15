import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline read context coordinator")
@MainActor
struct HomeTimelineReadContextCoordinatorTests {
    @Test("Read context projects follows once and reads filters only on demand")
    func projectsStableInputsOnce() {
        let data = ReadContextDataSpy(
            content: content(followedPubkeys: ["follow-a", "follow-b"])
        )
        let filter = ReadContextFilterSpy()
        var projectionCount = 0
        let coordinator = HomeTimelineReadContextCoordinator(
            data: data,
            filter: filter,
            currentTimestamp: { 321 },
            projectFollowedPubkeys: { pubkeys in
                projectionCount += 1
                return Set(pubkeys)
            }
        )
        let input = HomeTimelineReadContextInput(
            accountID: "account",
            fallbackEntries: [],
            resolvedRelayCount: 3,
            syncPolicy: .default(networkType: .wifi)
        )

        let unfiltered = coordinator.context(
            for: input,
            applyingHomeFilters: false
        )
        let filtered = coordinator.context(
            for: input,
            applyingHomeFilters: true
        )

        #expect(unfiltered.followedPubkeys == ["follow-a", "follow-b"])
        #expect(filtered.resolvedRelayCount == 3)
        #expect(filtered.syncPolicy == input.syncPolicy)
        #expect(projectionCount == 1)
        #expect(filter.reads == [
            ReadContextFilterRead(accountID: "account", timestamp: 321)
        ])

        data.content = content(followedPubkeys: ["follow-a", "follow-c"])
        let changed = coordinator.context(
            for: input,
            applyingHomeFilters: false
        )

        #expect(changed.followedPubkeys == ["follow-a", "follow-c"])
        #expect(projectionCount == 2)
    }

    private func content(
        followedPubkeys: [String]
    ) -> HomeTimelineContentSnapshot {
        HomeTimelineContentSnapshot(
            resolvedRelays: [],
            followedPubkeys: followedPubkeys,
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: true
        )
    }
}

@MainActor
private final class ReadContextDataSpy:
    HomeTimelineReadContextDataProviding {
    var content: HomeTimelineContentSnapshot
    var dependencies = HomeTimelineDependencyResolutionState(
        nip05Resolutions: [:],
        profileResolutionStates: [:]
    )

    init(content: HomeTimelineContentSnapshot) {
        self.content = content
    }

    var contentState: HomeTimelineContentSnapshot { content }

    var dependencyResolutionState: HomeTimelineDependencyResolutionState {
        dependencies
    }
}

private struct ReadContextFilterRead: Equatable {
    let accountID: String?
    let timestamp: Int
}

@MainActor
private final class ReadContextFilterSpy: HomeTimelineFilterManaging {
    private(set) var reads: [ReadContextFilterRead] = []

    func effectiveRuleSet(
        accountID: String?,
        now: Int
    ) -> NostrFilterRuleSet? {
        reads.append(ReadContextFilterRead(
            accountID: accountID,
            timestamp: now
        ))
        return nil
    }

    func suspend() -> Bool { false }

    func resume() -> Bool { false }
}
