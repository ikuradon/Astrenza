# DB-driven Nostr Timeline Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home TimelineをDB駆動のNostr timeline architectureへ段階移行し、UI状態、timeline同期判断、DB保存、materialize、relay runtimeを明確に分離する。

**Architecture:** 受信eventはまずDBへ保存し、Rowへ反映するかどうかはUI intentで決める。`NostrHomeTimelineStore` は最終的にPresentation Storeへ縮退し、`HomeTimelineCoordinator`、`HomeTimelineRepository`、`HomeTimelineEventIngestor`、`HomeTimelineSyncPlanner` に責務を移す。

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, GRDB-backed `NostrEventStore`, `NostrRelayRuntime`, `NostrHomeTimelineMaterializer`

---

## Current Problem

`Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift` が以下をまとめて持っている。

- UI state: `entries`, unread badge, live window, restore anchor
- Runtime event handling: `NostrRelayRuntimePacket` dispatch
- DB write: event保存、event source保存、timeline index保存
- Dependency planning: kind:0/source event/reply/repost/quote取得
- Materialization: DB/current projectionから `TimelineFeedEntry` 生成
- Relay runtime setup: default relay設定とforward REQ install

このままだと、スクロール、Gap、pull-to-refresh、relay reconnect、遅延解決、未読Pillが互いに影響しやすい。

## Target Shape

```text
UI
  HomeTimelineView
    ↓ user intent
Presentation Store
  NostrHomeTimelineStore
    ↓
Timeline Coordinator
  HomeTimelineCoordinator
    ↓                 ↘
Timeline Repository    Sync Planner
  HomeTimelineRepository  HomeTimelineSyncPlanner
    ↓                    ↓
Materializer + DB       Relay Runtime
  NostrTimelineMaterializer / NostrEventStore
                         ↓
                    Relay Session
                         ↓
                    WebSocket Transport

Relay Runtime packets
    ↓
Event Ingestor
  HomeTimelineEventIngestor
    ↓
DB / dependency hints
```

## Invariants

- Relayから受信したeventは即DBへ保存する。
- forward REQ由来のeventをRowへ即反映するのは、Timelineが最新windowにいてpending eventがない時だけ。
- スクロール中、過去方向閲覧中、Gap補完中はDB保存を優先し、Row化は明示的UI intentで行う。
- `RelayRuntime` はTimeline UIを知らない。
- `HomeTimelineEventIngestor` はUI stateを直接更新しない。
- `HomeTimelineRepository` はDB/current projectionからsnapshotを作るだけにする。
- `HomeTimelineSyncPlanner` は副作用を持たず、REQ packetや保存方針を返す。

## File Structure

### Create

- `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineEventIngestor.swift`
  - runtimeから受信したeventのDB保存、relay source記録、embedded repost target抽出を担当。

- `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineRepository.swift`
  - `NostrEventStore` と `NostrTimelineMaterializer` の橋渡し。
  - 初期段階では `TimelineFeedEntry` snapshot生成の薄いwrapperにする。

- `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift`
  - forward/older/gap/dependency REQ作成を集約。
  - 初期段階ではforward REQ計画から移す。

- `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineCoordinator.swift`
  - refresh/older/gap/live/pending materializationの司令塔。
  - 初期段階ではprotocolと最小実装を用意し、Storeから段階接続する。

### Modify

- `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - `HomeTimelineEventIngestor` を保持し、event保存処理を委譲する。
  - `HomeTimelineSyncPlanner` を保持し、forward REQ作成を委譲する。
  - 以後のTaskでmaterializeとdependency planningを切り出す。

- `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - EventIngestorとSyncPlannerの単体テストを追加する。
  - Store既存テストは維持する。

## Task 1: Event Ingestor Extraction

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineEventIngestor.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that verify:

```swift
@Test("Home timeline event ingestor stores event and relay source")
func homeTimelineEventIngestorStoresEventAndRelaySource() throws {
    let eventStore = try NostrEventStore.inMemory()
    let event = timelineEvent(idSeed: "ingest-note", pubkey: String(repeating: "a", count: 64), createdAt: 100)
    let ingestor = HomeTimelineEventIngestor(eventStore: eventStore)

    let result = try ingestor.ingest(event: event, relayURL: "wss://relay.example")

    #expect(result.savedEventIDs == [event.id])
    #expect(try eventStore.events(ids: [event.id]).map(\.id) == [event.id])
    #expect(try eventStore.eventSources(eventID: event.id).map(\.relayURL) == ["wss://relay.example"])
}
```

and:

```swift
@Test("Home timeline event ingestor stores embedded repost target")
func homeTimelineEventIngestorStoresEmbeddedRepostTarget() throws {
    let eventStore = try NostrEventStore.inMemory()
    let target = timelineEvent(idSeed: "ingest-repost-target", pubkey: String(repeating: "b", count: 64), createdAt: 90)
    let repost = timelineEvent(
        idSeed: "ingest-repost",
        pubkey: String(repeating: "a", count: 64),
        createdAt: 100,
        kind: 6,
        tags: [["e", target.id], ["p", target.pubkey]],
        content: target.eventJSON()
    )
    let ingestor = HomeTimelineEventIngestor(eventStore: eventStore)

    let result = try ingestor.ingest(event: repost, relayURL: "wss://relay.example")

    #expect(result.primaryEventID == repost.id)
    #expect(result.embeddedEventID == target.id)
    #expect(Set(try eventStore.events(ids: [repost.id, target.id]).map(\.id)) == [repost.id, target.id])
}
```

- [ ] **Step 2: Verify failing test**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: FAIL because `HomeTimelineEventIngestor` does not exist.

- [ ] **Step 3: Implement minimal ingestor**

Create:

```swift
import Foundation
import AstrenzaCore

struct HomeTimelineEventIngestResult: Equatable {
    let primaryEventID: String
    let embeddedEventID: String?
    let savedEventIDs: [String]
}

struct HomeTimelineEventIngestor {
    let eventStore: NostrEventStore?

    func ingest(event: NostrEvent, relayURL: String) throws -> HomeTimelineEventIngestResult {
        let embedded = embeddedRepostTarget(from: event)
        let eventsToSave = [event] + (embedded.map { [$0] } ?? [])
        try eventStore?.save(events: eventsToSave)
        try eventStore?.recordEventSources(eventIDs: eventsToSave.map(\.id), relayURL: relayURL)
        return HomeTimelineEventIngestResult(
            primaryEventID: event.id,
            embeddedEventID: embedded?.id,
            savedEventIDs: eventsToSave.map(\.id)
        )
    }

    func embeddedRepostTarget(from event: NostrEvent) -> NostrEvent? {
        guard event.kind == 6,
              let data = event.content.data(using: .utf8),
              let target = try? JSONDecoder().decode(NostrEvent.self, from: data),
              target.hasValidShape
        else { return nil }
        return target
    }
}
```

- [ ] **Step 4: Wire Store to ingestor**

In `NostrHomeTimelineStore`, add:

```swift
private let eventIngestor: HomeTimelineEventIngestor
```

Initialize it from `eventStore`:

```swift
self.eventIngestor = HomeTimelineEventIngestor(eventStore: eventStore)
```

Replace duplicate event save blocks in `handleHomeForwardEvent` and `handleBackwardEvent` with:

```swift
let ingestResult = try eventIngestor.ingest(event: event, relayURL: relayURL)
```

and derive embedded target from:

```swift
let embeddedTarget = ingestResult.embeddedEventID.flatMap { id in
    try? eventStore?.events(ids: [id]).first
}
```

- [ ] **Step 5: Verify**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineEventIngestor.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Extract home timeline event ingestor"
```

## Task 2: Forward REQ Planning Extraction

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Write failing test**

```swift
@Test("Home timeline sync planner builds forward reconnect packet")
func homeTimelineSyncPlannerBuildsForwardReconnectPacket() {
    let account = NostrAccount(pubkey: String(repeating: "a", count: 64), displayIdentifier: "npub-test", readOnly: true)
    let planner = HomeTimelineSyncPlanner()
    let packet = planner.forwardPacket(
        account: account,
        followedPubkeys: [String(repeating: "b", count: 64)],
        newestCreatedAt: 123,
        relayURLs: ["wss://relay.example"]
    )

    #expect(packet.subscriptionID == NostrHomeForwardREQBuilder.subscriptionID)
    #expect(packet.relayURLs == ["wss://relay.example"])
}
```

- [ ] **Step 2: Implement planner**

```swift
import Foundation
import AstrenzaCore

struct HomeTimelineSyncPlanner {
    func forwardPacket(
        account: NostrAccount,
        followedPubkeys: [String],
        newestCreatedAt: Int?,
        relayURLs: [String]
    ) -> NostrREQPacket {
        NostrHomeForwardREQBuilder.reconnectPacket(
            authors: followedPubkeys.isEmpty ? [account.pubkey] : followedPubkeys,
            newestCreatedAt: newestCreatedAt,
            relayURLs: relayURLs
        )
    }
}
```

- [ ] **Step 3: Wire Store**

Replace direct `NostrHomeForwardREQBuilder.reconnectPacket` call in `configureRelayRuntime` with `syncPlanner.forwardPacket(...)`.

- [ ] **Step 4: Verify and commit**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Commit:

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Extract home timeline sync planner"
```

## Task 3: Repository Snapshot Boundary

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineRepository.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Write failing test**

```swift
@Test("Home timeline repository materializes entries from projection")
@MainActor
func homeTimelineRepositoryMaterializesEntriesFromProjection() throws {
    let account = NostrAccount(pubkey: String(repeating: "a", count: 64), displayIdentifier: "npub-test", readOnly: true)
    let eventStore = try NostrEventStore.inMemory()
    let note = timelineEvent(idSeed: "repository-note", pubkey: account.pubkey, createdAt: 100)
    try eventStore.save(events: [note])

    let repository = HomeTimelineRepository(eventStore: eventStore)
    let snapshot = repository.materialize(
        account: account,
        noteEvents: [note],
        contextEvents: [],
        metadataEvents: [],
        nip05Resolutions: [:],
        followedPubkeys: [account.pubkey],
        resolvedRelays: ["wss://relay.example"],
        filterRules: nil
    )

    #expect(snapshot.entries.compactMap(\.post).map(\.id) == [note.id])
}
```

- [ ] **Step 2: Implement repository**

`HomeTimelineRepository` returns:

```swift
struct HomeTimelineMaterializedSnapshot: Equatable {
    var entries: [TimelineFeedEntry]
    var filterStatus: TimelineFilterStatus
    var renderFingerprint: [String]
}
```

It wraps `NostrTimelineMaterializer.entries(...)` and hides DB reads for deleted entries/timeline entries/media/link previews.

- [ ] **Step 3: Wire Store**

Move `materializeEntries()` DB query/materializer call into repository while keeping unread recomputation in Store.

- [ ] **Step 4: Verify and commit**

Run TimelineModelTests and commit:

```bash
git commit -m "Extract home timeline repository"
```

## Task 4: Runtime Packet Coordinator Boundary

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineCoordinator.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Introduce coordinator protocol**

```swift
protocol HomeTimelineCoordinating {
    func handleRuntimePacket(_ packet: NostrRelayRuntimePacket)
}
```

- [ ] **Step 2: Move packet classification**

Coordinator classifies:

- `.stateChanged`
- `.event`
- `.eose`
- `.closed`
- `.timeout`
- `.backwardCompleted`
- `.notice`
- `.auth`

Store still owns UI mutations during this task via closure callbacks.

- [ ] **Step 3: Verify and commit**

Run full app tests and commit:

```bash
git commit -m "Extract home timeline coordinator boundary"
```

## Task 5: Dependency Planning Boundary

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Move dependency grouping**

Move profile/source/gap/older REQ planning into `HomeTimelineSyncPlanner`.

- [ ] **Step 2: Keep queue state in Store temporarily**

Do not move `NostrDependencyFetchQueue` yet. Planner receives queue snapshots and returns packets.

- [ ] **Step 3: Verify and commit**

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
git commit -m "Extract home timeline dependency planning"
```

## Task 6: Presentation Store Slimming

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
- Test: `Astrenza/Tests/AstrenzaTests/HomeTimelineUnreadStateTests.swift`

- [ ] **Step 1: Keep only UI-facing state in Store**

Store should directly own:

- `entries`
- `phase`
- relay summary display values
- unread/pending counters
- scroll/anchor state

- [ ] **Step 2: Move non-UI operations into collaborators**

Move remaining runtime setup, materialization, dependency planning, and event ingest calls into collaborator methods.

- [ ] **Step 3: Verify and commit**

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
git commit -m "Slim home timeline presentation store"
```

## Task 7: Runtime Invariants and Regression Tests

**Files:**
- Modify: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add integration-style tests**

Cover:

- forward event saves to DB without immediate Row insert when not at newest window
- pending event count increments without changing `entries`
- live newest window materializes after event ingest
- relay reconnect does not require Store intervention to resume forward receive

- [ ] **Step 2: Run Core and app tests**

```bash
swift test --package-path Packages/AstrenzaCore
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
```

- [ ] **Step 3: Commit**

```bash
git commit -m "Add DB-driven timeline architecture regressions"
```

## Verification Matrix

- `swift test --package-path Packages/AstrenzaCore`
- `xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests`
- Manual simulator check:
  - login with NIP-05 or npub
  - Home TL initial display
  - relay status pill
  - pull-to-refresh
  - older pagination
  - GapRow backfill
  - live incoming event pending count

## Stop Conditions

Stop and re-plan if:

- Store tests need broad rewrites unrelated to collaborator boundaries.
- `TimelineFeedEntry` equality/fingerprint changes cause UI churn.
- A collaborator needs to own `@Published` state.
- Runtime packet handling starts requiring SwiftUI-specific state inside Core.

## Expected End State

- `NostrHomeTimelineStore` remains the UI-facing object.
- DB write and event source recording live in `HomeTimelineEventIngestor`.
- Forward REQ creation lives in `HomeTimelineSyncPlanner`.
- Materialized snapshots live behind `HomeTimelineRepository`.
- Runtime packet classification starts moving toward `HomeTimelineCoordinator`.
- Existing Home TL behavior remains unchanged.
