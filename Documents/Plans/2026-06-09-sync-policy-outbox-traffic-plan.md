# Sync Policy Outbox Traffic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home TLの取得漏れを減らしつつ、バッテリー、モバイル回線、relay BANリスクをSync Modeと通信量計測で制御する。

**Architecture:** 同期は `SyncPolicy` が予算を決め、`HomeTimelineSyncPlanner` がその予算に従ってREQをchunk化する。Nostr WebSocket payload通信量は `session` をメモリで、永続統計をhour bucketでGRDBへ保存し、Relay SheetとSettingsに表示する。Media/OGPはRow描画から直接fetchせず、tap/queue/policy経由に寄せる。

**Tech Stack:** Swift 6.1, SwiftUI, Swift Testing, GRDB 7.11, Nostr NIP-01/NIP-02/NIP-11/NIP-65/NIP-77.

---

## Scope

この計画は大きいので、実装を安全な順に分ける。

1. Traffic Accountingを先に入れて通信量を見える化する。
2. forward REQをchunk化し、巨大REQを避ける。
3. follow hard capを撤去し、Own Relay List modeで全followを対象にする。
4. Full Outbox modeでkind:3 relay hintとfollow先kind:10002を段階的に使う。
5. Media/OGPをpolicy/queue化して、Row描画で勝手に通信しないようにする。
6. Relay SheetとSettingsへ診断とmode選択を結線する。

## Definitions

### Sync Mode

```swift
public enum NostrSyncMode: String, Codable, CaseIterable, Sendable {
    case energySaver
    case ownRelayList
    case fullOutbox
}
```

### Network Policy

```swift
public enum NostrNetworkType: String, Codable, Sendable {
    case wifi
    case cellular
    case other
    case unknown
}

public struct NostrSyncPolicy: Codable, Equatable, Sendable {
    public var mode: NostrSyncMode
    public var networkType: NostrNetworkType
    public var lowPowerMode: Bool
    public var tapToLoadMedia: Bool
    public var queueOGPPreviews: Bool
    public var disableOGPOnCellular: Bool
    public var reduceFullOutboxOnCellular: Bool
}
```

### Traffic Accounting

MVPではWebSocket payload bytesのみを計測する。TCP/TLS/WebSocket frame overheadは含めない。表示では `Nostr traffic` と表記する。

```sql
relay_traffic_hourly_counters(
  account_id TEXT NOT NULL,
  relay_url TEXT NOT NULL,
  hour_start INTEGER NOT NULL,
  network_type TEXT NOT NULL,
  sync_mode TEXT NOT NULL,
  received_bytes INTEGER NOT NULL,
  sent_bytes INTEGER NOT NULL,
  received_messages INTEGER NOT NULL,
  sent_messages INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(account_id, relay_url, hour_start, network_type, sync_mode)
)
```

`session` はメモリのみ。Today / Last 24h / Current Cycle / month相当は `hour_start` の範囲SUMで算出する。daily rollupは後回し。

## Files

- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrSyncPolicy.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayTrafficModels.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayRuntime.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayRuntimeModels.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelaySession.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineLoader.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Relay/RelayStatusSheetView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: `Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift`

---

## Task 1: Add Sync Policy Models

**Files:**
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrSyncPolicy.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests:

```swift
@Test("Sync policy defaults to own relay list and tap-to-load on cellular")
func syncPolicyDefaults() {
    let wifi = NostrSyncPolicy.default(networkType: .wifi, lowPowerMode: false)
    #expect(wifi.mode == .ownRelayList)
    #expect(!wifi.tapToLoadMedia)
    #expect(wifi.queueOGPPreviews)

    let cellular = NostrSyncPolicy.default(networkType: .cellular, lowPowerMode: false)
    #expect(cellular.mode == .ownRelayList)
    #expect(cellular.tapToLoadMedia)
    #expect(cellular.disableOGPOnCellular)

    let lowPower = NostrSyncPolicy.default(networkType: .wifi, lowPowerMode: true)
    #expect(lowPower.mode == .energySaver)
    #expect(lowPower.tapToLoadMedia)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter syncPolicyDefaults
```

Expected: FAIL because `NostrSyncPolicy` does not exist.

- [ ] **Step 3: Implement models**

Create `NostrSyncPolicy.swift` with:

```swift
import Foundation

public enum NostrSyncMode: String, Codable, CaseIterable, Sendable {
    case energySaver
    case ownRelayList
    case fullOutbox
}

public enum NostrNetworkType: String, Codable, CaseIterable, Sendable {
    case wifi
    case cellular
    case other
    case unknown
}

public struct NostrSyncPolicy: Codable, Equatable, Sendable {
    public var mode: NostrSyncMode
    public var networkType: NostrNetworkType
    public var lowPowerMode: Bool
    public var tapToLoadMedia: Bool
    public var queueOGPPreviews: Bool
    public var disableOGPOnCellular: Bool
    public var reduceFullOutboxOnCellular: Bool

    public init(
        mode: NostrSyncMode,
        networkType: NostrNetworkType,
        lowPowerMode: Bool,
        tapToLoadMedia: Bool,
        queueOGPPreviews: Bool,
        disableOGPOnCellular: Bool,
        reduceFullOutboxOnCellular: Bool
    ) {
        self.mode = mode
        self.networkType = networkType
        self.lowPowerMode = lowPowerMode
        self.tapToLoadMedia = tapToLoadMedia
        self.queueOGPPreviews = queueOGPPreviews
        self.disableOGPOnCellular = disableOGPOnCellular
        self.reduceFullOutboxOnCellular = reduceFullOutboxOnCellular
    }

    public static func `default`(
        networkType: NostrNetworkType = .unknown,
        lowPowerMode: Bool = false
    ) -> NostrSyncPolicy {
        let constrained = lowPowerMode || networkType == .cellular
        return NostrSyncPolicy(
            mode: lowPowerMode ? .energySaver : .ownRelayList,
            networkType: networkType,
            lowPowerMode: lowPowerMode,
            tapToLoadMedia: constrained,
            queueOGPPreviews: true,
            disableOGPOnCellular: networkType == .cellular,
            reduceFullOutboxOnCellular: true
        )
    }
}
```

- [ ] **Step 4: Verify**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter syncPolicyDefaults
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrSyncPolicy.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Add Nostr sync policy model"
```

---

## Task 2: Persist Hourly Relay Traffic Counters

**Files:**
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayTrafficModels.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests:

```swift
@Test("Relay traffic counters accumulate by hour relay network and sync mode")
func relayTrafficCountersAccumulate() throws {
    let store = try NostrEventStore.inMemory()
    let hour = 1_717_891_200
    let first = NostrRelayTrafficDelta(
        accountID: "account",
        relayURL: "wss://relay.example",
        occurredAt: hour + 30,
        networkType: .wifi,
        syncMode: .ownRelayList,
        receivedBytes: 120,
        sentBytes: 40,
        receivedMessages: 2,
        sentMessages: 1
    )
    let second = NostrRelayTrafficDelta(
        accountID: "account",
        relayURL: "wss://relay.example",
        occurredAt: hour + 600,
        networkType: .wifi,
        syncMode: .ownRelayList,
        receivedBytes: 80,
        sentBytes: 10,
        receivedMessages: 1,
        sentMessages: 1
    )

    try store.recordRelayTraffic([first, second])

    let totals = try store.relayTrafficTotals(
        accountID: "account",
        start: hour,
        end: hour + 3_600
    )
    #expect(totals.receivedBytes == 200)
    #expect(totals.sentBytes == 50)
    #expect(totals.receivedMessages == 3)
    #expect(totals.sentMessages == 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter relayTrafficCountersAccumulate
```

Expected: FAIL because traffic models/store methods do not exist.

- [ ] **Step 3: Implement models**

Create `NostrRelayTrafficModels.swift` with:

```swift
import Foundation

public struct NostrRelayTrafficDelta: Equatable, Sendable {
    public var accountID: String
    public var relayURL: String
    public var occurredAt: Int
    public var networkType: NostrNetworkType
    public var syncMode: NostrSyncMode
    public var receivedBytes: Int
    public var sentBytes: Int
    public var receivedMessages: Int
    public var sentMessages: Int
}

public struct NostrRelayTrafficTotals: Equatable, Sendable {
    public var receivedBytes: Int
    public var sentBytes: Int
    public var receivedMessages: Int
    public var sentMessages: Int

    public static let zero = NostrRelayTrafficTotals(
        receivedBytes: 0,
        sentBytes: 0,
        receivedMessages: 0,
        sentMessages: 0
    )
}
```

- [ ] **Step 4: Add GRDB migration and store methods**

In `NostrEventStore.migrate()`, add migration `addRelayTrafficHourlyCounters`.

Add methods:

```swift
public func recordRelayTraffic(_ deltas: [NostrRelayTrafficDelta]) throws
public func relayTrafficTotals(accountID: String, start: Int, end: Int) throws -> NostrRelayTrafficTotals
public func relayTrafficTotalsByRelay(accountID: String, start: Int, end: Int) throws -> [String: NostrRelayTrafficTotals]
```

Use `hourStart = occurredAt - occurredAt % 3600`.

- [ ] **Step 5: Verify**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter relayTrafficCountersAccumulate
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayTrafficModels.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Persist relay traffic counters"
```

---

## Task 3: Count WebSocket Payload Bytes in Relay Runtime

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelaySession.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayRuntime.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing tests**

Add a unit test around a pure counter helper before wiring to live WebSocket:

```swift
@Test("Relay traffic meter counts UTF8 payload bytes")
func relayTrafficMeterCountsPayloadBytes() {
    var meter = NostrRelayTrafficMeter(accountID: "account", relayURL: "wss://relay.example", policy: .default(networkType: .wifi))
    meter.recordSent(#"["REQ","sub",{}]"#)
    meter.recordReceived(#"["EOSE","sub"]"#)

    let deltas = meter.flush(occurredAt: 1_717_891_234)

    #expect(deltas.count == 1)
    #expect(deltas[0].sentBytes == #"["REQ","sub",{}]"#.utf8.count)
    #expect(deltas[0].receivedBytes == #"["EOSE","sub"]"#.utf8.count)
    #expect(deltas[0].sentMessages == 1)
    #expect(deltas[0].receivedMessages == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter relayTrafficMeterCountsPayloadBytes
```

Expected: FAIL because `NostrRelayTrafficMeter` does not exist.

- [ ] **Step 3: Implement meter**

Add `NostrRelayTrafficMeter` to `NostrRelayTrafficModels.swift`. It should buffer session counters in memory and emit one delta on flush.

- [ ] **Step 4: Wire runtime/session**

Expose an optional traffic callback from `NostrRelaySession` to `NostrRelayRuntime`.

Rules:
- Count sent text immediately before WebSocket send.
- Count received text/data immediately after receive.
- Do not write DB from the receive loop directly.
- Runtime batches deltas and flushes to `NostrEventStore.recordRelayTraffic` every 1-5 seconds or when enough bytes accumulated.

- [ ] **Step 5: Verify**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter relayTrafficMeterCountsPayloadBytes
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayTrafficModels.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelaySession.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayRuntime.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Count relay payload traffic"
```

---

## Task 4: Chunk Forward REQs

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayRuntime.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayRuntimeModels.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing tests**

Add:

```swift
@Test("Forward REQ scheduler chunks large author filters")
func forwardREQSchedulerChunksAuthors() {
    let authors = (0..<251).map { String(format: "%064x", $0) }
    let packet = NostrHomeForwardREQBuilder.packet(authors: authors, since: 100, relayURLs: ["wss://relay.example"])

    let chunks = NostrREQScheduler.forwardChunks(packet, policy: .init(maxAuthorsPerFilter: 100, maxIDsPerFilter: 250))

    #expect(chunks.count == 3)
    #expect(chunks[0].filters.first?.authors?.count == 100)
    #expect(chunks[1].filters.first?.authors?.count == 100)
    #expect(chunks[2].filters.first?.authors?.count == 51)
    #expect(Set(chunks.map(\.subscriptionID)).count == 3)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter forwardREQSchedulerChunksAuthors
```

Expected: FAIL because `forwardChunks` does not exist.

- [ ] **Step 3: Implement scheduler helper**

Add `NostrREQScheduler.forwardChunks(_:)`. It must:
- chunk by authors.
- preserve relayURLs.
- preserve forward strategy.
- suffix subscription IDs deterministically: `astrenza-home-forward-0`, `astrenza-home-forward-1`.
- keep original packet unchanged if chunking is unnecessary.

- [ ] **Step 4: Use it in runtime**

In `NostrRelayRuntime.installForward`, replace direct `session.install(forwardPacket)` with installation of scheduled chunks.

- [ ] **Step 5: Verify**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter forwardREQSchedulerChunksAuthors
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayRuntime.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayRuntimeModels.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Chunk home forward requests"
```

---

## Task 5: Remove Follow Hard Caps Under Own Relay List Mode

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineLoader.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift`

- [ ] **Step 1: Write failing tests**

Add:

```swift
@Test("Home timeline sync planner keeps all followed authors before runtime chunking")
func homeTimelinePlannerKeepsAllFollowedAuthors() throws {
    let account = NostrAccount(pubkey: String(repeating: "f", count: 64), displayIdentifier: "account", readOnly: true)
    let authors = (0..<753).map { String(format: "%064x", $0) }
    let packet = HomeTimelineSyncPlanner().forwardPacket(
        account: account,
        followedPubkeys: authors,
        newestCreatedAt: nil,
        relayURLs: ["wss://relay.example"]
    )

    #expect(packet.filters.first?.authors?.count == 753)
}
```

- [ ] **Step 2: Run test to verify it fails if caps are still present**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/NostrTimelineSyncTests/homeTimelinePlannerKeepsAllFollowedAuthors
```

Expected: FAIL if planner caps authors.

- [ ] **Step 3: Remove caps**

Remove:
- `NostrHomeTimelineLoader.bootstrapState` `.prefix(256)` for contacts.
- `NostrHomeTimelineLoader.initialState` `.prefix(256)` contacts and `.prefix(128)` planner authors.
- `NostrHomeTimelineLoader.refreshedState` `.prefix(128)`.
- `NostrHomeTimelineLoader.olderState` `.prefix(128)`.
- `HomeTimelineSyncPlanner.timelineAuthors` `.prefix(128)`.
- `NostrHomeTimelineStore.databaseBackfillEvents` `.prefix(128)`.
- Local gap window `.prefix(128)` only after chunk/gap safety is in place.

- [ ] **Step 4: Verify**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/NostrTimelineSyncTests/homeTimelinePlannerKeepsAllFollowedAuthors
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineLoader.swift Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift
git commit -m "Keep all followed authors for timeline sync"
```

---

## Task 6: Add Own Relay List Planner

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift`
- Test: `Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift`

- [ ] **Step 1: Write failing tests**

Add:

```swift
@Test("Own relay list mode sends all authors only to account read relays")
func ownRelayListPlannerUsesAccountReadRelays() {
    let authors = (0..<300).map { String(format: "%064x", $0) }
    let relays = ["wss://read1.example", "wss://read2.example"]
    let plan = HomeTimelineSyncPlanner().forwardPlan(
        account: NostrAccount(pubkey: String(repeating: "a", count: 64), displayIdentifier: "account", readOnly: true),
        followedPubkeys: authors,
        newestCreatedAt: nil,
        relayURLs: relays,
        policy: .default(networkType: .wifi)
    )

    #expect(plan.packets.allSatisfy { $0.relayURLs == relays })
    #expect(plan.totalAuthorCount == 300)
}
```

- [ ] **Step 2: Implement `HomeTimelineForwardPlan`**

Add:

```swift
struct HomeTimelineForwardPlan {
    let packets: [NostrREQPacket]
    let totalAuthorCount: Int
    let mode: NostrSyncMode
}
```

`forwardPlan` returns one logical packet before runtime chunking for `ownRelayList`.

- [ ] **Step 3: Verify**

Run the test.

- [ ] **Step 4: Commit**

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift
git commit -m "Plan home sync by sync mode"
```

---

## Task 7: Add Full Outbox Author Relay Grouping

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrOutboxModels.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrCore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: `Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift`

- [ ] **Step 1: Write tests**

Add tests that kind:3 p-tag relay hints become author relay candidates:

```swift
@Test("Contact list exposes pubkeys with relay hints")
func contactListPubkeysWithRelayHints() {
    let first = String(repeating: "a", count: 64)
    let second = String(repeating: "b", count: 64)
    let event = nostrEvent(kind: 3, tags: [
        ["p", first, "wss://one.example"],
        ["p", second],
        ["p", first, "wss://two.example"]
    ])

    let items = NostrContactList.items(from: event)

    #expect(items.first { $0.pubkey == first }?.relayHints == ["wss://one.example", "wss://two.example"])
    #expect(items.first { $0.pubkey == second }?.relayHints == [])
}
```

- [ ] **Step 2: Implement contact items**

Add `NostrContactListItem` with `pubkey` and `relayHints`.

- [ ] **Step 3: Add outbox grouping**

`fullOutbox` policy builds groups:
- relay hint group if present.
- own read relays fallback if no hint.
- future follow kind:10002 relays can override/add candidates.

- [ ] **Step 4: Verify**

Run package and app tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrOutboxModels.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrCore.swift Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineSyncPlanner.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift
git commit -m "Group home authors by outbox relay hints"
```

---

## Task 8: Queue Media and OGP Fetches Behind Policy

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrContentAttachmentClassifier.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkPreviewResolver.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineMediaProjection.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineContentProjection.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write tests**

Add tests:
- Media URL is classified but not fetched by classification.
- OGP resolver can be scheduled without immediate network fetch when policy queues OGP.
- cellular + `disableOGPOnCellular` returns pending/tap-required state.

- [ ] **Step 2: Implement queue contract**

Add lightweight request model:

```swift
public enum NostrRemotePreviewRequestKind: String, Codable, Sendable {
    case media
    case linkPreview
}

public struct NostrRemotePreviewRequest: Codable, Equatable, Sendable {
    public var url: URL
    public var kind: NostrRemotePreviewRequestKind
    public var eventID: String
    public var requestedAt: Int
}
```

- [ ] **Step 3: Wire UI projection**

Projection produces pending attachments. View tap triggers resolver/queue.

- [ ] **Step 4: Verify**

Run tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrContentAttachmentClassifier.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkPreviewResolver.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineMediaProjection.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineContentProjection.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Gate media and OGP fetching by sync policy"
```

---

## Task 9: Surface Sync Diagnostics in Relay Sheet

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Relay/RelayModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Relay/RelayStatusSheetView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift`

- [ ] **Step 1: Write tests**

Add tests for a pure view model:
- session bytes format.
- today bytes format.
- current cycle bytes format.
- relay rows include received/sent payload bytes.

- [ ] **Step 2: Implement diagnostics model**

Add:

```swift
struct RelayTrafficSummary: Equatable {
    var session: NostrRelayTrafficTotals
    var today: NostrRelayTrafficTotals
    var currentCycle: NostrRelayTrafficTotals
    var byRelay: [String: NostrRelayTrafficTotals]
}
```

- [ ] **Step 3: Wire store**

Store reads:
- session counters from runtime.
- today/current cycle from GRDB hourly counters.

- [ ] **Step 4: Update Relay Sheet**

Replace misleading live-only Received/Sent with:
- Session
- Today
- Current Cycle
- Relay detail rows.

- [ ] **Step 5: Verify**

Run app tests.

- [ ] **Step 6: Commit**

```bash
git add Astrenza/Sources/AstrenzaApp/Components/Relay/RelayModels.swift Astrenza/Sources/AstrenzaApp/Components/Relay/RelayStatusSheetView.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift
git commit -m "Show relay traffic diagnostics"
```

---

## Task 10: Add Settings for Relays and Sync

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Relay/RelaySettingsView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrSessionStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift`

- [ ] **Step 1: Add settings model tests**

Test:
- default mode is `.ownRelayList`.
- low power mode can suggest `.energySaver`.
- full outbox on cellular can be reduced when toggle is on.

- [ ] **Step 2: Place UI**

Settings path:

```text
Settings > Account > Relays & Sync
```

Sections:
- Sync Mode
- Data Saver
- Traffic
- Reset Statistics

- [ ] **Step 3: Persist per-account policy**

Persist policy in app settings for each account. Do not make it global-only.

- [ ] **Step 4: Reconfigure runtime on policy change**

Changing mode should reinstall forward plan after a short debounce. Avoid closing and reopening WebSockets unless relay set changes.

- [ ] **Step 5: Verify**

Run app tests and Simulator smoke test.

- [ ] **Step 6: Commit**

```bash
git add Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift Astrenza/Sources/AstrenzaApp/Components/Relay/RelaySettingsView.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrSessionStore.swift Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift
git commit -m "Add relays and sync settings"
```

---

## Verification Commands

Run after each core task:

```bash
swift test --package-path Packages/AstrenzaCore
```

Run after each app task:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
```

Run after completing all tasks:

```bash
swift test --package-path Packages/AstrenzaCore
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Risks

- Removing follow caps before forward chunking can make relay requests too large.
- Full Outbox without relay score can open too many relays.
- Writing traffic counters on every message can reintroduce scroll jank.
- OGP/media queue must not block Row rendering.
- Relay traffic is payload traffic, not full network accounting.

## Done Criteria

- User can choose Energy Saver / Own Relay List / Full Outbox.
- Own Relay List mode no longer drops follows due to `prefix(256/128)`.
- Forward REQ is chunked.
- Relay Sheet shows session/today/current cycle sent/received bytes.
- Media/OGP fetch behavior follows policy.
- Tests cover planner author counts, chunking, traffic accounting, and policy defaults.
