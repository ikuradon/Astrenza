# Astrenza.zip 一次確認レビュー

対象: `/mnt/data/Astrenza.zip`  
展開先: `/mnt/data/astrenza_old_unzip/Astrenza.old`  
確認日: 2026-06-14

## 1. 結論

このZIPは、Nostr core / GRDB local event store / relay runtime / projection / media resolver の探索はかなり進んでいる一方、Home Timeline UI は「旧仕様のSwiftUI prototypeに、Nostr固有の機能とIvory風の表現を継ぎ足していった結果、Design SystemとTimeline実装契約が追いつかなくなった」状態に見える。

Production Home Timelineとして延命するより、以下の扱いが安全。

1. 現在のZIPを `legacy-swiftui-timeline-prototype` として保存する。
2. Core / DB / projection / media resolver / fixture / Maestro意図は残す。
3. Home Timeline本体は `UICollectionView + DiffableDataSource + UIHostingConfiguration` で新設する。
4. 既存SwiftUI Timelineは、比較用fixture・UI失敗例・テストケース抽出元として扱う。

## 2. 確認した構成

- App: `Astrenza/Sources/AstrenzaApp`
- Core package: `Packages/AstrenzaCore`
- Media resolver service: `Services/AstrenzaMediaResolver`
- UI reference screenshots: `Documents/Screenshot/Ivory`
- Maestro flows: `.maestro`
- Plans / Research: `Documents/Plans`, `Documents/Research`
- Git repository included: `.git`
- SwiftPM checkout included: `Packages/AstrenzaCore/.build/checkouts/GRDB.swift`

Size summary:

- whole extracted project: about 376 MB
- `Astrenza`: about 1.4 MB
- `Packages/AstrenzaCore`: about 285 MB, mostly vendored checkouts/build artifacts
- `Documents`: about 41 MB
- `.git`: about 44 MB

The uploaded ZIP should not be shared externally as-is because it includes `.git`, `.build`, `__MACOSX`, and local project artifacts.

## 3. Build/test確認

This environment has Swift but no Xcode / Apple SDK, so the iOS app target could not be built or typechecked.

Attempted:

- `swift test` in `Packages/AstrenzaCore`
  - failed before compilation because SwiftPM attempted to fetch or resolve package repositories from a cache path that is not present in this environment.
- `npm test` in `Services/AstrenzaMediaResolver`
  - failed because `node_modules` is not included and `vitest` is unavailable.

So this review is a source-level and structure-level audit, not a successful build verification.

## 4. Static counts

`Astrenza/Sources/AstrenzaApp`:

- Swift files: 79
- Swift lines: about 22,676
- `.font(.system...)`: 335
- numeric `.padding(...)`: 260
- numeric `.frame(...)`: 137
- numeric `cornerRadius`: 87
- `Color(red:)`: 26
- numeric `.opacity(...)`: 229
- animation / withAnimation / spring / snappy: 113
- `GeometryReader`: 10
- `PreferenceKey`: 24
- `LazyVStack`: 1
- `ScrollView`: 10
- `UICollectionView`: 0
- `UIHostingConfiguration`: 0

This is the clearest evidence that the UI is not currently protected by a strong Design System or production Timeline engine contract.

## 5. 良い部分

### 5.1 Core / DBの方向は良い

`NostrEventStore` has a real GRDB-backed event store with:

- `events`
- `event_tags`
- `replaceable_heads`
- `addressable_heads`
- `timeline_entries`
- `sync_cursors`
- `relay_profiles`
- `event_sources`
- deletion tombstones
- NIP-51 lists
- `media_assets`
- `link_previews`
- outbox tables
- relay traffic counters

This matches the current direction: normalized event store + lightweight timeline index + read-time projection.

### 5.2 Projection tests already exist

The app has tests around timeline projection order, dedupe, indexed deleted rows, gap handling, and coalesced projection refreshes. This is valuable and should be preserved.

### 5.3 Media resolver service is promising

`Services/AstrenzaMediaResolver` already contains:

- SSRF-style URL guard
- HTML metadata parsing
- image header probing
- blurhash generation
- auth tests
- resolver route tests

This is a good foundation for OGP / Media delayed resolve, but it must be connected to UI through fixed layout contracts.

### 5.4 Maestro flows capture intent

The `.maestro` flows cover action menu, compose, media, post detail, timeline restore, scrolling, and relay status. Even if the implementation is rewritten, these flows are useful as acceptance-test intent.

## 6. Design崩壊の主因

### 6.1 Timeline本体がSwiftUI ScrollView + LazyVStack

`TimelineFeedView.swift` uses:

- `ScrollView`
- `LazyVStack`
- `ScrollPosition`
- `GeometryReader`
- `PreferenceKey`
- manual layout cache
- manual viewport anchor restoration
- pull-to-refresh
- gap backfill
- floating action menu positioning
- read marker readable IDs

This is too much responsibility for one SwiftUI view if the target is Tweetbot/Ivory-grade Timeline stability. It is exactly the area that should move to `UICollectionView`.

### 6.2 Action button contract is too small

Current baseline:

```swift
static let actionHeight: CGFloat = 22
static let actionIconSize: CGFloat = 15
```

`TimelinePostActionButton` sets only a 22pt height and max width. Even if the surrounding row makes the visual area seem acceptable, the action itself is not aligned with the new v0.4 baseline of visual icon around 22pt and tap target at least 44x44pt.

### 6.3 Design tokens exist but are too thin

`AstrenzaTheme.swift` has some global metrics and colors, but most screens still use raw font sizes, raw padding, raw frame sizes, raw opacity, raw radius, and ad-hoc colors.

This causes drift: every new feature adds slightly different visual decisions.

### 6.4 TimelineAttachments.swift is too large

`TimelineAttachments.swift` is about 1125 lines and contains:

- media grid
- single media layout
- sensitive/protected overlay
- tap-to-load overlay
- fullscreen media viewer
- gallery paging
- zoom/pan gestures
- remote media loader
- blurhash decoder
- link preview card
- unresolved link card
- remote link image loader

This should be split into Design System components and state machines:

- `MediaGrid`
- `MediaTileView`
- `SensitiveOverlay`
- `LinkPreviewCard`
- `LinkPreviewSkeleton`
- `TimelineFullscreenMediaViewer`
- `RemoteImageLoader`
- `BlurHashPlaceholder`

### 6.5 Splash currently hides relay/timeline readiness

`AstrenzaRootView` keeps `AstrenzaStartupSplashView` visible until `hasPresentedStartupTimeline` and content readiness conditions pass. The splash says `Connecting relays...`.

This conflicts with the newer policy:

- Launch Screen should not hide DB restore or relay sync.
- Root shell should display immediately.
- Only the timeline area may use a short restore gate.
- Network must not be waited before first interactive timeline.

### 6.6 NostrHomeTimelineStore is too large

`NostrHomeTimelineStore.swift` is about 2228 lines and combines:

- relay/runtime handling
- timeline index persistence
- projection windowing
- unread logic
- link preview resolving
- dependency fetch
- profile/detail helpers
- status diagnostics
- filter application

It works as an exploratory store, but production UI needs thinner, reason-specific stores/coordinators so row updates do not cascade unpredictably.

### 6.7 Delayed resolve can still change layout too freely

Current UI supports OGP, media, custom emoji, quote, reply, repost, and profile resolution, but the layout contract is implicit. Some good fixed values exist, but there is no central `TimelineRowLayoutContract` proving:

- OGP pending/resolved have same reserved height.
- media pending/loaded keep same aspect/height.
- profile/@prefix resolution does not increase line count unexpectedly.
- quote/reply/repost target arrival does not insert/remove rows.
- sensitive reveal does not mutate row identity.

### 6.8 Visual snapshot tests are missing

There are model/projection tests and Maestro flows, but no component-level visual snapshot test suite for:

- text-only row
- CW row
- OGP pending/resolved/failed
- media pending/loaded/sensitive
- quote pending/resolved/unavailable
- reply context
- repost context
- long Japanese text
- Dynamic Type / dark / black / high contrast

## 7. 残すべきもの

Keep:

- `Packages/AstrenzaCore`
- `NostrEventStore` direction
- `timeline_entries` and projection tests
- relay planner and diagnostics logic
- media resolver service
- Ivory screenshot reference set
- `.maestro` intent flows
- mock timeline data, after converting it into explicit design fixtures

## 8. 凍結・作り直し候補

Freeze or rewrite:

- `TimelineFeedView.swift`
- `TimelinePostRow.swift`
- `TimelineAttachments.swift`
- `TimelinePostActionButton.swift`
- `AstrenzaStartupSplashView.swift`
- startup splash control in `AstrenzaRootView`
- glass-heavy Home chrome
- raw font/spacing/radius usage in app screens

## 9. 推奨リカバリ順

1. Tag this archive as `legacy-swiftui-timeline-prototype`.
2. Do not continue adding UI features to the old Timeline.
3. Extract `DesignSystem` package/module:
   - tokens
   - typography
   - spacing
   - radius
   - icon metrics
   - density
   - timeline row contract
   - component states
4. Create new production `TimelineCollectionViewController`:
   - `UICollectionView`
   - diffable data source
   - item IDs only in snapshots
   - `UIHostingConfiguration` for SwiftUI row body
   - anchor capture/restore before and after every snapshot mutation
5. Rebuild Timeline row from fixtures:
   - text
   - CW
   - media grid
   - sensitive media
   - GitHub/Pixiv OGP
   - reply context
   - repost context
   - quote card
6. Add snapshot tests before adding more screens.
7. Add XCUITest/Maestro checks for delayed resolve and scroll position invariants.
8. Remove splash-as-sync-mask and replace it with root shell + timeline restore gate.

## 10. 最終判断

The project should not be thrown away. The data/core side contains useful work. But the Home Timeline UI should not be rescued by incremental styling. The design collapse is structural: the timeline engine, component state contracts, and design tokens are missing or too weak.

Production direction should be:

```text
SwiftUI app shell
UICollectionView timeline engine
SwiftUI row body via UIHostingConfiguration
DesignSystem tokens everywhere
Delayed resolve as explicit row states
Snapshot + E2E as release blockers
```
