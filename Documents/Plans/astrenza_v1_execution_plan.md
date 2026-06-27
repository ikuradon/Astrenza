# Astrenza v1 Execution Plan

Status: Phase 0/1 complete; Phase 5 scaffold complete; Phase 6 fixture contracts mostly complete; Phase 4 DB/read-state bridge audit is the next priority.
Updated: 2026-06-27
Scope: living planning and audit document. This plan does not authorize production DB wiring, production Home Timeline wiring, SQL schema changes, or legacy SwiftUI Timeline extension by itself.

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

## Current Progress Snapshot

- Phase 0 guardrails are complete: root `AGENTS.md`, this execution plan, and `Documents/Plans/astrenza_v1_pr_checklist.md` define source-of-truth, Archive, salvage, Timeline, DesignSystem, security, and validation rules.
- Phase 1 DesignSystem v0 skeleton is complete enough for current Timeline contract work: `Packages/DesignSystem` exists, is wired through `project.yml`, has Timeline metrics/contracts, package tests, and `scripts/guard_designsystem.sh`.
- Phase 5 TimelineEngine scaffold is complete enough for offline scaffold tests: `TimelineSurface`, `TimelineCollectionViewController`, diffable data source, snapshot coordinator, position recorder, visible range tracker, prefetch coordinator, and diagnostics recorder exist under `Astrenza/Sources/AstrenzaApp/TimelineEngine`. It is not wired into production Home.
- Phase 6 row-state / projection / resolve apply contracts are mostly complete for fixture-backed offline work: `TimelineEntryViewState`, row projection boundary, resolve apply expectations, resolve snapshot diagnostics, and `ResolveCoordinatorBoundary` fake boundary tests exist. A real DB-backed `ResolveCoordinator` actor and resolver runtime are still intentionally absent.
- Phase 7 diagnostics / restore gate / artifact contracts are complete enough for the offline phase: `TimelineDiagnosticsExport`, restore gate budget tests, and `Documents/Plans/timeline_diagnostics_artifact_contract.md` exist. Production root shell restore integration and E2E coverage remain pending.
- Phase 4 DB/read-state bridge is now the next priority. `Documents/Specifications/astrenza_local_db_schema_v0_2.sql` remains the source-of-truth schema and should not be changed yet. Current `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift` still uses `timeline_entries`, so real DB-backed Timeline and ResolveCoordinator work must wait for a bridge/adaptor decision.

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

Status: Complete.

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

Status: Complete for the v0 skeleton and static guard baseline. Future Timeline components still need to use these contracts instead of raw styling.

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
- `swift test --package-path Packages/DesignSystem`
- Future app integration: `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>'`

## Phase 2: Typed IDs And Module Boundary Cleanup

Status: Partial. TimelineEngine-local IDs exist, but Core/App boundaries still contain raw `String` IDs and need a migration map before broader production wiring.

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

Status: Partial. Fixture-driven Timeline projection and fake relay-style tests exist, but a shared test-support module, URLProtocol stub, fake media loader, and manifest convention remain pending.

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

Status: Next priority. The audit is documented in `Documents/Plans/timeline_db_bridge_audit.md`; no production DB adapter, SQL schema change, migration, or dual-write is authorized yet.

Deliverables:
- Gap analysis between current `NostrEventStore`/timeline entries and v0.2 `feeds`, `feed_items`, `feed_read_state`, `resolve_jobs`, and diagnostics schema.
- Decision record for whether to migrate current `timeline_entries` into `feed_items` or maintain a temporary adapter.
- Read marker vs scroll anchor audit and tests.
- A no-schema-change bridge note stating that v0.2 schema remains source-of-truth and current `NostrEventStore` still uses `timeline_entries`.

Acceptance criteria:
- read marker advances only on actual visibility or explicit user action.
- launch, sync, EOSE, foreground, and resolve do not advance read marker.
- `pending_new` does not enter the visible query automatically.
- SQL schema changes are avoided unless a spec-backed migration is planned.
- Any future bridge PR chooses one of: adapter-only contract, temporary dual-write with explicit migration plan, or backfill/migration plan with rollback tests.

Likely test commands:
- `swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests`
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>' -only-testing:AstrenzaTests/HomeTimelineUnreadStateTests`
- Targeted SQL/doc review against `Documents/Specifications/astrenza_local_db_schema_v0_2.sql`
- Future bridge contract tests proving `timeline_entries` source data maps deterministically to v0.2-like `feed_items` draft rows without changing schema.

## Phase 5: UICollectionView TimelineEngine Scaffold

Status: Scaffold complete for offline tests. Production Home wiring is still blocked until Phase 4 bridge and restore/read-state boundaries are closed.

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

Status: Mostly complete for fixture-backed offline contracts. Real DB-backed `ResolveCoordinator`, `resolve_jobs` execution, network/media resolver work, and production runtime wiring remain pending.

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
- `ResolveCoordinatorBoundaryIssue.Kind` has all-cases issue coverage when the boundary changes.

Likely test commands:
- `swift test --package-path Packages/AstrenzaCore`
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>' -only-testing:AstrenzaTests/TimelineModelTests`
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>' -only-testing:AstrenzaTests/ResolveCoordinatorBoundaryContractTests`
- Future rendered snapshot/E2E tests for pending/resolved/failed/blocked row states.

## Phase 7: Launch Restore Gate And No-Network-Wait E2E

Status: Offline diagnostics and artifact contracts are complete enough for planning. Production root shell restore gate wiring, DB-backed local query integration, and E2E coverage remain pending.

Deliverables:
- Root shell first-paint policy separated from Timeline restore gate.
- `TimelineRestoreGate` limited to Timeline area and local snapshot/anchor restore.
- Diagnostics for root shell first paint, local query, initial snapshot apply, anchor restore, first interactive scroll, and network wait.
- `TimelineDiagnosticsExport` artifact contract documented at `Documents/Plans/timeline_diagnostics_artifact_contract.md` as local/offline/debug/failure-artifact data only, with no external telemetry upload without an explicit future privacy decision.
- E2E scenarios for offline relay, cached anchor restore, empty cache, and slow DB fallback to inline skeleton.

Acceptance criteria:
- Launch Screen or app-wide splash does not wait for relay, EOSE, OGP, media, profile, search, pruning, or checkpoint.
- first interactive timeline scroll waits 0ms for network.
- cached anchor restores without transient newest/top flash.
- restore gate duration respects the v1 budget or switches to inline skeleton.
- `summary.restoreGateMetrics` remains decodable by offline consumers without Home/Timeline runtime wiring, DB queries, relay startup, or network work.
- `networkWaitedBeforeInteractiveScrollMS > 0` and `readMarkerChanged == true` are release-blocking diagnostics.

Likely test commands:
- `xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>' -only-testing:AstrenzaUITests`
- `maestro test .maestro/timeline-restore.yaml` only after Java Runtime and a built simulator app are available.

## Phase 8: Snapshot / E2E / Benchmark Hardening

Status: Pending, aside from lower-level diagnostics/model contracts.

Deliverables:
- Snapshot matrix for text, long Japanese, OGP, media, profile fallback, repost, quote, reply, Dynamic Type, high contrast, and black theme.
- E2E matrix for launch restore, pending_new, delayed resolve, visible mute, pruning fallback, publish partial failure, account switch, and Dynamic Type XXL.
- Benchmark seeds for 10k, 100k, and eventually 1M events.
- Failure artifacts: before/after screenshots, visible item keys, anchor frames, read marker diff, DB/resolve diagnostics, and `TimelineDiagnosticsExport` JSON when privacy checks pass.

Acceptance criteria:
- Timeline/resolve PRs fail on anchor delta > 2pt in representative scenarios.
- Release blockers from v1 spec are covered by tests or documented manual audits.
- Benchmark output JSON is stored with device/runtime metadata.
- CI policy distinguishes PR small set, nightly full matrix, and release benchmark gates.
- Failure artifacts do not include `nsec`, secret key material, raw event JSON, raw private content, or private relay/account material.

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

## Immediate Next Task

Close Phase 4 with a docs/test-only DB bridge contract slice before any real DB-backed Timeline or ResolveCoordinator work. Start with an adapter-only source-model test that maps current `timeline_entries + events` data into v0.2-like `feed_items` draft rows, records explicit gaps for read state, `pending_new`, render hints, and `resolve_jobs`, and keeps `Documents/Specifications/astrenza_local_db_schema_v0_2.sql` unchanged.
