# Astrenza v1 Execution Plan

Status: guardrails before implementation
Updated: 2026-06-25
Scope: documentation and repository guardrails only. This plan does not authorize a Timeline rewrite by itself.

## Current Repo State Summary

- Branch: `main` tracking `origin/main`; initial inspection showed a clean worktree, with a non-fatal `.git/fsmonitor--daemon.ipc` warning from `git status`.
- Layout: iOS app under `Astrenza/Sources/AstrenzaApp`, SwiftPM core package under `Packages/AstrenzaCore`, media resolver service under `Services/AstrenzaMediaResolver`, specs/plans/research under `Documents`.
- Project structure: `project.yml` drives an iOS 26 app through XcodeGen and references `Astrenza.xcodeproj`.
- Swift package: `Packages/AstrenzaCore/Package.swift` targets Swift 6.1, iOS 26, macOS 15, and depends on `GRDB.swift`, `secp256k1.swift`, and `negentropy-swift`.
- Existing tests: app tests in `Astrenza/Tests/AstrenzaTests`; core tests in `Packages/AstrenzaCore/Tests/AstrenzaCoreTests`; media resolver Vitest tests in `Services/AstrenzaMediaResolver/test`.
- Existing CI: no `.github` directory was present at inspection time.
- Existing documentation: canonical/spec docs in `Documents/Specifications`, many older plans in `Documents/Plans`, Superpowers plans in `docs/superpowers/plans`, Maestro smoke intent in `.maestro`.
- Legacy Timeline state: `HomeTimelineView` calls `TimelineFeedView`; `TimelineFeedView` uses `ScrollView`, `LazyVStack`, `ScrollPosition`, `GeometryReader`, and `PreferenceKey`. This path is not the v1 production Timeline target.
- Local tools observed: Xcode 27.0, Swift 6.4, XcodeGen 2.45.4, Node 22.23.1, npm 10.9.8. Maestro is installed but blocked by a missing Java Runtime in this environment.

## Source-Of-Truth Hierarchy

1. Canonical v1 spec: `Documents/Specifications/astrenza_nostr_client_development_spec.md`.
2. Supporting source-of-truth: `Documents/Specifications/README.md`, `Documents/Specifications/astrenza_local_db_schema_v0_2.sql`, `Documents/Specifications/astrenza_local_db_schema_v0_2_migration.sql`.
3. Current code and tests, only where they do not conflict with the canonical v1 spec.
4. Archive/reference only: `Documents/Specifications/Archive/astrenza_nostr_client_development_spec_v0_4.md` and `Documents/Specifications/Archive/astrenza_legacy_zip_review.md`.

Do not implement from Archive documents when v1 differs.

## Do Not Modify Or Extend For Production

- Do not add production Timeline behavior to `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift`.
- Do not production-extend `TimelinePostRow.swift`, `TimelineAttachments.swift`, or `TimelinePostActionButton.swift` as the v1 Timeline path.
- Do not add more production behavior to SwiftUI `ScrollView` / `LazyVStack` Timeline surfaces.
- Do not preserve `AstrenzaStartupSplashView` as a network/relay readiness mask.
- Do not add raw color, raw spacing, raw font size, or ad-hoc icon size to new Timeline components.
- Do not make delayed resolve update row identity, delete/insert visible rows, or advance read marker.
- Do not make relay, OGP, media, profile sync, search, pruning, checkpoint, or optimize block first interactive Timeline restore.

## Salvage List

- `Packages/AstrenzaCore`, especially Nostr parsing, validation, relay, event store, sync, publisher, media resolver client, and policy code.
- GRDB/SQLite direction and the v0.2 schema concepts: immutable raw events, rebuildable projections, `feed_items`, `feed_read_state`, `resolve_jobs`, `timeline_snapshot_diagnostics`.
- Existing projection/read-state tests: `NostrTimelineProjectionTests`, `NostrTimelineSyncTests`, `HomeTimelineUnreadStateTests`, `TimelineModelTests`, and core timeline index tests.
- Relay planner/diagnostics and Nostr runtime logic in app/core code, after boundary cleanup.
- `Services/AstrenzaMediaResolver` OGP/media resolver foundation and tests.
- `.maestro` flows as acceptance-test intent, not as proof that v1 Timeline is implemented.
- `MockTimelineData`, existing screenshots, and older fixtures as sources for explicit v1 fixture data.

## Phase 0: Guardrails / AGENTS.md / Plan

Deliverables:
- Root `AGENTS.md` with canonical source-of-truth, Archive, salvage, Timeline, DesignSystem, security, validation, and final-response rules.
- This execution plan at `Documents/Plans/astrenza_v1_execution_plan.md`.
- PR checklist at `Documents/Plans/astrenza_v1_pr_checklist.md`.

Acceptance criteria:
- Future agents can identify the canonical spec and know not to implement from Archive.
- Legacy SwiftUI Timeline production extension is explicitly blocked.
- No app behavior, dependencies, SQL schema, or legacy Swift files are changed in this phase.

Likely test commands:
- `git status --short --branch`
- `find Documents/Specifications -maxdepth 3 -type f | sort`
- `find . -name AGENTS.md -print`

## Phase 1: DesignSystem v0 Skeleton And Tokens

Deliverables:
- `Packages/DesignSystem` package or target, wired through `project.yml` only after a scoped plan.
- Token skeletons for semantic color, typography, spacing, radius, icon, control size, media metrics.
- Timeline contracts: `TimelineDensity`, `TimelineRowMetrics`, `TimelineRowLayoutContract`, and row skeleton states.
- Initial lint or static scan policy for raw Timeline UI constants.

Acceptance criteria:
- New Timeline components can be built without raw color/spacing/icon constants.
- 44x44pt action hit target contract is represented in tokens.
- Token changes that affect row height have a documented snapshot/E2E requirement.

Likely test commands:
- `xcodegen generate`
- `swift test --package-path Packages/AstrenzaCore`
- Future: DesignSystem package tests or `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>'`

## Phase 2: Typed IDs And Module Boundary Cleanup

Deliverables:
- Spec-aligned typed IDs: `EventID`, `Pubkey`, `RelayURL`, `FeedID`, `TimelineEntryID`, and account/timeline keys where needed.
- Boundary notes for AppShell, TimelineEngine, Store, ProjectionLayer, RelayManager, ResolveCoordinator, and PublishQueue.
- Migration map from current `String`-heavy paths to typed IDs.

Acceptance criteria:
- New code does not pass raw `String` IDs across module boundaries.
- Store remains UI-independent; TimelineEngine does not parse Nostr events or write DB directly.
- Existing Core/DB/projection tests remain salvageable.

Likely test commands:
- `swift test --package-path Packages/AstrenzaCore`
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>'`
- Targeted `rg` scan for new raw ID usage in modified files.

## Phase 3: TestFixtureRuntime / FakeRelay / URLProtocolStub / FakeMediaLoader

Deliverables:
- `AstrenzaTestSupport` or equivalent test-support module.
- `FakeRelay` with `emit`, `emitEOSE`, manual delay, `OK`, `CLOSED`, `AUTH`, and `NOTICE` controls.
- `URLProtocolStub` for OGP success, timeout, malformed HTML, and blocked URL.
- `FakeMediaLoader` for aspect-known, aspect-unknown, thumbnail success/failure, full image success/failure.
- Fixture manifest convention for launch and delayed resolve scenarios.

Acceptance criteria:
- UI/E2E tests can run without live relay or web dependencies.
- Delayed resolve scenarios can be manually triggered by tests.
- Fixtures contain no `nsec` or secret material.

Likely test commands:
- `swift test --package-path Packages/AstrenzaCore`
- Future app test plan: `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>'`
- `npm test --prefix Services/AstrenzaMediaResolver` when media resolver dependencies are installed.

## Phase 4: Home Feed / Read-State Audit Against v0.2 Schema

Deliverables:
- Gap analysis between current `NostrEventStore`/timeline entries and v0.2 `feeds`, `feed_items`, `feed_read_state`, `resolve_jobs`, and diagnostics schema.
- Decision record for whether to migrate current `timeline_entries` into `feed_items` or maintain a temporary adapter.
- Read marker vs scroll anchor audit and tests.

Acceptance criteria:
- read marker advances only on actual visibility or explicit user action.
- launch, sync, EOSE, foreground, and resolve do not advance read marker.
- `pending_new` does not enter the visible query automatically.
- SQL schema changes are avoided unless a spec-backed migration is planned.

Likely test commands:
- `swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests`
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>' -only-testing:AstrenzaTests/HomeTimelineUnreadStateTests`
- Targeted SQL/doc review against `Documents/Specifications/astrenza_local_db_schema_v0_2.sql`

## Phase 5: UICollectionView TimelineEngine Scaffold

Deliverables:
- New TimelineEngine scaffold separate from legacy SwiftUI Timeline path.
- `TimelineSurface` bridge, `TimelineCollectionViewController`, `UICollectionViewDiffableDataSource`, `CellRegistration`, and `UIHostingConfiguration` row body.
- `TimelineSnapshotCoordinator`, `TimelinePositionRecorder`, `TimelineVisibleRangeTracker`, `TimelinePrefetchCoordinator`, and diagnostics hooks.

Acceptance criteria:
- Snapshot items are stable `TimelineEntryID` values only.
- All snapshot mutations go through `TimelineSnapshotCoordinator`.
- UIKit owns visible range, prefetch, anchor capture, and anchor restore.
- Legacy `TimelineFeedView` remains frozen and is not extended as fallback production UI.

Likely test commands:
- `xcodegen generate`
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>'`
- Future E2E: launch restore and pending_new representative tests.

## Phase 6: Timeline Row View-State Projection And Delayed Resolve Contract

Deliverables:
- `TimelineEntryViewState` projection aligned with v1 `ResolveState`.
- `TimelineRowLayoutContract` applied to row view state.
- Resolve application path that invalidates row model cache and uses reconfigure-style updates.
- Projection tests for OGP, media, profile, repost, quote, and reply parent transitions.

Acceptance criteria:
- row identity remains `TimelineEntryID` / `feed_items.item_key` before and after resolve.
- failed resolve keeps note visible through fallback state.
- visible row resolve does not mutate read marker.
- Home row height changes are bounded by layout contract; rich expansion moves to detail/thread.

Likely test commands:
- `swift test --package-path Packages/AstrenzaCore`
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>' -only-testing:AstrenzaTests/TimelineModelTests`
- Future snapshot tests for pending/resolved/failed/blocked row states.

## Phase 7: Launch Restore Gate And No-Network-Wait E2E

Deliverables:
- Root shell first-paint policy separated from Timeline restore gate.
- `TimelineRestoreGate` limited to Timeline area and local snapshot/anchor restore.
- Diagnostics for root shell first paint, local query, initial snapshot apply, anchor restore, first interactive scroll, and network wait.
- E2E scenarios for offline relay, cached anchor restore, empty cache, and slow DB fallback to inline skeleton.

Acceptance criteria:
- Launch Screen or app-wide splash does not wait for relay, EOSE, OGP, media, profile, search, pruning, or checkpoint.
- first interactive timeline scroll waits 0ms for network.
- cached anchor restores without transient newest/top flash.
- restore gate duration respects the v1 budget or switches to inline skeleton.

Likely test commands:
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>' -only-testing:AstrenzaUITests`
- `maestro test .maestro/timeline-restore.yaml` only after Java Runtime and a built simulator app are available.

## Phase 8: Snapshot / E2E / Benchmark Hardening

Deliverables:
- Snapshot matrix for text, long Japanese, OGP, media, profile fallback, repost, quote, reply, Dynamic Type, high contrast, and black theme.
- E2E matrix for launch restore, pending_new, delayed resolve, visible mute, pruning fallback, publish partial failure, account switch, and Dynamic Type XXL.
- Benchmark seeds for 10k, 100k, and eventually 1M events.
- Failure artifacts: before/after screenshots, visible item keys, anchor frames, read marker diff, DB/resolve diagnostics.

Acceptance criteria:
- Timeline/resolve PRs fail on anchor delta > 2pt in representative scenarios.
- Release blockers from v1 spec are covered by tests or documented manual audits.
- Benchmark output JSON is stored with device/runtime metadata.
- CI policy distinguishes PR small set, nightly full matrix, and release benchmark gates.

Likely test commands:
- `swift test --package-path Packages/AstrenzaCore`
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>'`
- Future benchmark command or scheme after benchmark target exists.
- `npm test --prefix Services/AstrenzaMediaResolver` for resolver service changes.

## Known Environment Limitations

- This inspection environment has Xcode and Swift, but simulator availability must be checked before promising iOS UI/E2E results.
- Maestro currently fails because Java Runtime is missing; Maestro flows are acceptance intent until Java and a simulator app are available.
- Network is restricted in the Codex sandbox. Package resolution, npm install, remote relay probes, and live docs require explicit approval or an outside-sandbox tool path.
- Do not claim Swift/Xcode/UI tests passed unless the exact command was run fresh and exited 0.
- Documentation-only phases should still run cheap repository/document checks and record why app tests were not necessary or not run.

## Immediate Next Task After Phase 0

Prepare Phase 1 with a scoped DesignSystem v0 skeleton plan. The task should inspect current `AstrenzaTheme`, timeline raw constants, and existing row components, then create only the module/package skeleton and token contracts needed before any UICollectionView Timeline rewrite.
