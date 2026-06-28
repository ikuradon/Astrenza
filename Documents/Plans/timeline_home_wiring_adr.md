# TimelineEngine Home Wiring ADR

## 1. Status

Proposed.

This ADR is docs-only. It records the future production Home wiring strategy for the new TimelineEngine restore pipeline. It does not authorize or implement production Home wiring.

## 2. Context

The legacy SwiftUI Home path remains the current production Home surface. `AstrenzaRootView` still owns the root shell/session flow, and `HomeTimelineView` still renders the production timeline through the legacy SwiftUI `TimelineFeedView` path.

The new TimelineEngine/Core Store pipeline is ready for offline and source-model acceptance, but it is not yet wired into production Home. The existing offline path covers:

- Core `TimelineRepositoryStore` read-only boundary.
- App `TimelineRepositoryStoreWindowComposer`.
- App `TimelineRepositoryStore` diagnostics mapping.
- `TimelineInitialRestoreUseCase`.
- `TimelineInitialRestoreCoordinatorAdapter`.
- TimelineEngine scaffold, `TimelineSnapshotCoordinator`, `TimelinePositionRecorder`, and `TimelineDiagnosticsRecorder`.

Schema v0.2 remains unchanged. DB write paths, resolver execution, relay sync, media/OGP/profile resolver connection, and production root/Home wiring remain out of scope.

The v1 source-of-truth still requires the production Timeline direction to be `UICollectionView` + `UICollectionViewDiffableDataSource` + `UIHostingConfiguration`, with DesignSystem tokens treated as runtime contracts rather than optional styling.

Current production launch behavior also has a known future rollout gap: the root shell and app-wide startup splash are still coupled to Home readiness. A future wiring PR must separate root shell first paint from the Timeline-area restore gate before enabling the collection view Home path by default.

## 3. Decision

Future production Home wiring will introduce an explicit engine mode flag, modeled as `AstrenzaTimelineEngineMode`, with a launch argument such as `--timeline-engine=collectionView`.

The default mode remains legacy SwiftUI Home until the rollout gates in this ADR pass. The first collection view rollout is Home-only; Mentions, Profile, Thread, List, and Search surfaces remain separate future decisions.

The running session must not automatically fall back from the collection view path to legacy Home after Home has started mutating visible state. Rollback is a restart-time or debug-switch choice that selects the legacy path before route construction, not a same-session dual-render or hidden failover.

`AstrenzaRootView` root shell behavior remains unchanged by this ADR. Future implementation must preserve immediate root shell first paint and must not wait for relay, network, resolver, search, pruning, checkpoint, or EOSE work before the first interactive Timeline scroll.

## 4. Dependency Injection Plan

Future Home wiring should construct the new path through a narrow dependency container rather than allowing Home views to directly create DB, network, relay, or resolver objects. The initial dependency set is:

- `TimelineRepositoryStore`.
- `TimelineRepositoryStoreWindowComposer`.
- `TimelineInitialRestoreUseCase`.
- `TimelineInitialRestoreCoordinatorAdapter` or its production runtime equivalent.
- `TimelineCollectionViewController` / `TimelineSurface`.
- Row model projector / `TimelineEntryViewState` projector.
- `TimelineSnapshotCoordinator`.
- Persisted-anchor restore executor.
- `TimelineDiagnosticsRecorder` and diagnostics sink.
- Fake/test runtime dependencies for fixture Home and app-hosted tests.

The Core store dependency should be injected as the read-only `TimelineRepositoryStore` boundary. UIKit and SwiftUI surfaces must not own SQL strings, `GRDB` handles, relay clients, or resolver queues.

Home wiring must not call relay or network work before local initial restore. It must not write the read marker during launch, restore, sync, EOSE, foreground, or resolve. It must not mutate `feed_items.pending_new` during restore. It must not call `dataSource.apply` outside `TimelineSnapshotCoordinator`.

## 5. Legacy Home Boundary

Legacy SwiftUI Home remains frozen except for bug fixes and required compatibility maintenance. No new feature work should be added to `TimelineFeedView`, `TimelinePostRow`, `TimelineAttachments`, or their `ScrollView` / `LazyVStack` production timeline path.

Legacy Home can remain the default and fallback while the collection view path matures. The old and new paths must not both observe and mutate the visible dataset or read marker at the same time.

Any shared store used by the new path remains read-only until a separate write-path ADR explicitly opens DB write scope.

## 6. Feature Flag / Rollout Gates

The collection view Home path can only be enabled behind the engine mode flag after all of these gates pass:

- A local fixture Home launch uses the new path without production relay, network, or resolver startup.
- Restore plan to coordinator expectation tests pass.
- An initial `UICollectionView` surface smoke test passes.
- Startup logs show no network startup before local restore, including no `LocalDataTask`, `ATS`, `nw_`, `WebSocketTask`, `URLSessionWebSocketTask`, `wss://`, or `setDefaultRelays` activity for the selected restore path.
- Restore diagnostics keep `readMarkerChanged == false`.
- Restore diagnostics keep `networkWaitedBeforeInteractiveScrollMS == 0`.
- Visible rows exclude `pending_new` by default.
- Visible rows exclude hidden rows by default.
- Missing-target quote and repost rows remain in the snapshot with fallback render state.
- Selected `xcodebuild` suites execute non-zero Swift Testing tests.
- The manual debug switch and launch argument are documented.
- Root shell first paint is proven independent from Timeline restore readiness.

## 7. Rollback Criteria

Keep the flag off, or roll back to legacy mode on the next launch, if any of these occur:

- First paint waits for network, relay EOSE, resolver, search, pruning, checkpoint, or optimize work.
- The visible timeline jumps or briefly shows newest/top before restoring the saved anchor.
- Read marker advances during launch, restore, sync, EOSE, foreground, or resolve.
- `pending_new` inserts automatically without user action or an explicit top-of-feed policy.
- `dataSource.apply` is called outside `TimelineSnapshotCoordinator`.
- Old and new Home both observe or mutate the visible dataset/read marker.
- Core Store query results diverge from source-model tests.
- Row projection changes item identity.

## 8. Next Implementation Sequence

Do not jump directly to full production Home wiring. Use this sequence:

1. Add a test-only `TimelineSurface` dependency container.
2. Add an offscreen or no-window `TimelineCollectionViewController` smoke test if feasible.
3. Apply the initial snapshot through `TimelineSnapshotCoordinator` with a fake collection view or pure harness.
4. Add the `AstrenzaTimelineEngineMode` feature flag model and launch argument parser.
5. Add a root/Home route adapter behind the flag without changing root shell launch behavior.
6. Only then wire a limited Home collection view path.

## 9. Explicit Forbidden Scope

This ADR does not open:

- SQL schema changes.
- DB migration.
- DB write paths.
- Real `ResolveCoordinator` actor implementation.
- `resolve_jobs` execution.
- Relay, network, media resolver, OGP resolver, or profile resolver connection.
- External telemetry.
- GitHub Actions changes.
- Legacy Home feature work.
- Read marker advancement during launch, restore, sync, EOSE, foreground, or resolve.
- Production root shell, splash, or route behavior changes.

Diagnostics for this pipeline remain local/debug/failure-artifact only until a separate privacy decision explicitly opens another destination.

## 10. Required Tests For Future Wiring PR

Future wiring PRs should include focused RED-first coverage before production integration:

- `TimelineHomeEngineModeTests`.
- `TimelineSurfaceDependencyContainerTests`.
- `TimelineCollectionViewInitialRestoreSmokeTests`.
- `TimelineHomeRouteFlagTests`.
- `launch_does_not_wait_for_network`.
- `launch_restore_cached_anchor_no_visible_jump`.
- `pending_new_not_inserted_until_user_action`.
- `read_marker_not_advanced_by_restore`.
- `dataSourceApply_coordinator_only`.
