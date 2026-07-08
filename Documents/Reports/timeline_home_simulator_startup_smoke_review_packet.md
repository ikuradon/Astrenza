# TimelineHome Simulator Startup Smoke Review Packet

Generated: 2026-07-08 21:14:42 +0900

## 1. Review Target

- repo: `https://github.com/ikuradon/Astrenza.git`
- branch: `main`
- evidence target commit: `311d31001a3379650a4bd745b76816b74209db6c`
- evidence target commit message: `test: verify TimelineHome collectionView route in simulator startup smoke`
- packet attachment commit: out-of-band final pushed SHA; intentionally not self-embedded in this file.
- review-start `HEAD == origin/main`: `311d31001a3379650a4bd745b76816b74209db6c == 311d31001a3379650a4bd745b76816b74209db6c`
- review-start latest commit: `311d31001a3379650a4bd745b76816b74209db6c test: verify TimelineHome collectionView route in simulator startup smoke`
- review-start worktree: clean; `git -c core.fsmonitor=false status --short --branch` returned only `## main...origin/main`.
- Phase A review result: PASS. Blocking issues were not found.

## 2. Result Bundles

These are local evidence paths only. They are not uploaded artifacts and do not open export, telemetry, CI artifact upload, analytics, remote logging, or file-writer scope.

- fixed simulator startup smoke result bundle path: `/private/tmp/astrenza_311d310_simulator_startup_20260708T1147Z.xcresult`
- selected app suite result bundle path: `/private/tmp/astrenza_311d310_selected_app_suites_20260708T1147Z.xcresult`
- destination used: `platform=iOS Simulator,name=iPhone 17,OS=26.5`
- fixed bundle `.xcresult` tree: `TimelineHomeCollectionViewSimulatorStartupSmokeTests=16`, total suites `1`, total tests `16`, zero suites `0`.
- selected bundle `.xcresult` tree: total selected app suites `40`, total selected tests `611`, zero selected suite count `0`.

## 3. Simulator Startup Smoke Evidence

- simulator startup smoke exists as `TimelineHomeCollectionViewSimulatorStartupSmokeTests`.
- existing app-hosted `AstrenzaTests` simulator path is used.
- no UI-test target was added.
- default/no-flag startup stays legacy.
- flagged startup requires `--timeline-engine=collectionView`.
- flagged startup requires a clean evaluated Root body wiring gate.
- unevaluated wiring gate stays legacy even when it looks otherwise clean.
- clean evaluated flagged path selects `collectionView`.
- root shell first paint is preserved.
- Timeline restore gate remains Timeline-area-only.
- `networkWaitedBeforeInteractiveScrollMS == 0`.
- `readMarkerChanged == false`.
- result DTO is `Codable`, round-trips, and remains privacy-safe.
- raw `launchArguments`, raw result-bundle lines, and raw excerpts are not encoded.

## 4. Boundary Proof

- Phase B packet scope: docs/report-only.
- Phase B production source changes: none.
- Phase B test changes: none.
- Phase B CI / `.github` changes: none.
- evidence target `311d310` changes are test-only: five files under `Astrenza/Tests/AstrenzaTests`.
- no startup network.
- no DB write.
- no read marker advancement.
- no `feed_read_state` mutation.
- no `pending_new` mutation.
- no Root-owned `dataSource.apply`.
- no extra `NostrHomeTimelineStore`.
- `dataSource.apply` remains `TimelineSnapshotCoordinator`-only in production source.
- Root/Home/splash production behavior unchanged by this packet.
- legacy SwiftUI Timeline unchanged by this packet.
- SQL/migration unchanged by this packet.
- `.github` unchanged by this packet.
- `project.yml`, package/dependency files, and `Astrenza.xcodeproj` unchanged by this packet.
- no upload/export telemetry.
- no `ResolveCoordinator` actor scope opened.

## 5. Fixed Result Bundle Startup-Network Scan

Scan target: `/private/tmp/astrenza_311d310_simulator_startup_20260708T1147Z.xcresult`

The scan output is token-count-only. Raw result-bundle lines are not included.

| Token | Count |
| --- | ---: |
| `LocalDataTask` | 0 |
| `ATS failure` | 0 |
| `nw_` | 0 |
| `WebSocket` | 0 |
| `URLSessionWebSocketTask` | 0 |
| `wss://` | 0 |
| `setDefaultRelays` | 0 |
| relay connection attempts | 0 |

- startup-network scan result: pass / clean.
- plain `URLSession` duplicate-class warning handling: no startup-network attempt is inferred from a plain duplicate-class warning. Such a warning is environment noise only when every stronger startup-network token above remains `0`.

## 6. Privacy Scan

Scan target: fixed bundle evidence plus encoded simulator startup smoke result.

Required forbidden-fragment policy list:

- `nsec`
- `secret`
- `privateKey` / `private_key`
- `raw_json`
- `rawEvent` / `raw_event`
- `mnemonic`
- `keychain`
- `nostr secret`
- relay URL
- pubkey
- event id
- private message content phrase
- `launchArguments`

Privacy scan result:

| Fragment | Count In Evidence Payload |
| --- | ---: |
| `nsec` | 0 |
| `secret` | 0 |
| `privateKey` / `private_key` | 0 |
| `raw_json` | 0 |
| `rawEvent` / `raw_event` | 0 |
| `mnemonic` | 0 |
| `keychain` | 0 |
| `nostr secret` | 0 |
| relay URL value | 0 |
| pubkey value | 0 |
| event id value | 0 |
| private message content phrase | 0 |
| raw `launchArguments` payload | 0 |

- policy-token appearances in this packet are policy/checklist terms only, not leaked data.
- no relay URL value, pubkey value, event ID value, raw private content, raw result-bundle line, raw excerpt, or secret-like value is included.

## 7. Selected Suite Counts

Counts below come from the `311d310` review evidence and were cross-checked against the selected app suite `.xcresult` tree.

| Suite | Swift Testing count |
| --- | ---: |
| `TimelineHomeCollectionViewSimulatorStartupSmokeTests` | 16 |
| `TimelineHomeRootBodyRenderSwitchTests` | 23 |
| `TimelineHomeStartupSmokeLocalGateReportTests` | 22 |
| `TimelineHomeFlaggedCollectionViewStartupSmokeTests` | 25 |
| `TimelineHomeStartupSmokeEvidenceBundleTests` | 15 |
| `TimelineHomeStartupSmokeDiagnosticsAttachmentTests` | 20 |
| `TimelineHomeCollectionViewRouteRestoreIntegrationTests` | 16 |
| `TimelineHomeRootBodyActivationWiringGateConsumerTests` | 18 |
| `TimelineHomeRootBodyActivationWiringGateTests` | 16 |
| `TimelineHomeCollectionViewRouteActivationSwitchTests` | 19 |
| `TimelineHomeRootActivationDecisionSnapshotChainConsumerTests` | 14 |
| `TimelineHomeRootActivationDecisionSnapshotChainTests` | 15 |
| `TimelineHomeRootActivationPreflightTests` | 17 |
| `TimelineHomeActivationArtifactChainConsumerTests` | 17 |
| `TimelineHomeCollectionViewRouteActivationReadinessConsumerTests` | 16 |
| `TimelineHomeCollectionViewRouteActivationTests` | 24 |
| `TimelineHomeCollectionViewRouteBehindFlagConstructionTests` | 22 |
| `TimelineHomeConstructionArtifactChainConsumerTests` | 15 |
| `TimelineHomeCollectionViewOffscreenConstructionHarnessResultConsumerTests` | 16 |
| `TimelineHomeCollectionViewOffscreenConstructionHarnessTests` | 16 |
| `TimelineHomeRouteConstructionPlanConsumerTests` | 12 |
| `TimelineHomeRouteConstructionReadinessTests` | 16 |
| `TimelineHomeCollectionViewRouteConstructionTests` | 6 |
| `TimelineHomeRootRouteDecisionSnapshotConsumerTests` | 14 |
| `TimelineHomeRootRouteDecisionSnapshotTests` | 8 |
| `TimelineHomeRootRouteDiagnosticsSinkInjectionTests` | 14 |
| `TimelineHomeRouteDiagnosticsSinkTests` | 11 |
| `TimelineHomeRootRouteCallSiteTests` | 13 |
| `TimelineHomeRootRoutePreflightTests` | 18 |
| `TimelineHomeRootRouteGuardTests` | 19 |
| `TimelineHomeRouteDiagnosticsTests` | 14 |
| `TimelineHomeRouteHostTests` | 14 |
| `TimelineHomeRouteIntegrationSkeletonTests` | 18 |
| `TimelineHomeRouteAdapterTests` | 10 |
| `TimelineHomeLaunchRestoreContractTests` | 13 |
| `TimelineHomeEngineModeTests` | 6 |
| `TimelineSurfaceDependencyContainerTests` | 7 |
| `TimelineCollectionViewControllerSmokeTests` | 3 |
| `TimelineInitialRestoreSnapshotCoordinatorHarnessTests` | 8 |
| `TimelineEngineScaffoldTests` | 25 |

- total selected app suites: 40
- total selected tests: 611
- zero selected suite count: 0

## 8. Validation Commands

The `311d310` review evidence included these validation commands or checks:

- `git checkout main && git fetch origin main && git pull --ff-only origin main`
- `git rev-parse HEAD`
- `git rev-parse origin/main`
- `git -c core.fsmonitor=false status --short --branch`
- `xcodegen generate`
- `scripts/guard_designsystem.sh`
- `scripts/guard_timeline_diagnostics_artifact.sh --self-test`
- `swift test --package-path Packages/DesignSystem`
- `swift test --package-path Packages/AstrenzaCore`
- `swift test --package-path Packages/AstrenzaCore --filter TimelineRepositoryStore`
- fixed `xcodebuild test` for `TimelineHomeCollectionViewSimulatorStartupSmokeTests` with `-resultBundlePath /private/tmp/astrenza_311d310_simulator_startup_20260708T1147Z.xcresult`
- selected app `xcodebuild test` suites with `-resultBundlePath /private/tmp/astrenza_311d310_selected_app_suites_20260708T1147Z.xcresult`
- `xcodebuild build`
- `xcrun xcresulttool get test-results tests --path /private/tmp/astrenza_311d310_simulator_startup_20260708T1147Z.xcresult --compact`
- `xcrun xcresulttool get test-results tests --path /private/tmp/astrenza_311d310_selected_app_suites_20260708T1147Z.xcresult --compact`
- `git diff --check`
- startup-network grep / token scan for the fixed simulator startup bundle
- privacy grep / forbidden-fragment scan for fixed bundle evidence and encoded simulator startup smoke result
- targeted scope checks for source, tests, CI, SQL/migration, project/dependency, Root/Home/splash, and legacy SwiftUI Timeline paths

Current packet validation before commit/push:

- `xcodegen generate`: pass; project regenerated from `project.yml`.
- `scripts/guard_designsystem.sh`: pass; `DesignSystem static guard passed`.
- `scripts/guard_timeline_diagnostics_artifact.sh --self-test`: pass; safe sample passed and unsafe sample was rejected.
- `swift test --package-path Packages/DesignSystem`: pass after sandbox cache retry outside the default sandbox; Swift Testing `10 tests in 4 suites`.
- `xcodebuild test ... -only-testing:AstrenzaTests/TimelineHomeCollectionViewSimulatorStartupSmokeTests`: pass; result bundle `/private/tmp/astrenza_packet_validation_20260708T1217Z_simulator_startup.xcresult`; Swift Testing `16 tests in 1 suite`; zero suite count `0`.
- `xcodebuild test ... -only-testing:AstrenzaTests/TimelineHomeStartupSmokeLocalGateReportTests`: pass; result bundle `/private/tmp/astrenza_packet_validation_20260708T1217Z_local_gate.xcresult`; Swift Testing `22 tests in 1 suite`; zero suite count `0`.
- `xcodebuild test ... -only-testing:AstrenzaTests/TimelineHomeFlaggedCollectionViewStartupSmokeTests`: pass; result bundle `/private/tmp/astrenza_packet_validation_20260708T1217Z_flagged_startup.xcresult`; Swift Testing `25 tests in 1 suite`; zero suite count `0`.
- `xcrun xcresulttool get test-results tests --path <packet-validation-bundles> --compact`: pass after sandbox `TestReport` retry outside the default sandbox.
- `git diff --check`: pass for tracked diff before staging.
- `git diff --cached --check`: pass for staged diff.
- staged scope checks: pass; only `Documents/Reports/timeline_home_simulator_startup_smoke_review_packet.md` is staged, with no `Astrenza/Sources/**`, `Astrenza/Tests/**`, SQL/migration, `.github`, project/dependency, Root/Home/splash, or legacy SwiftUI Timeline changes.
- startup-network grep of this packet: pass; matches are the required token-count rows only.
- privacy grep of this packet: pass; matches are policy/checklist terms only.
- subagent evidence packet audit: PASS.
- subagent privacy audit: PASS.
- subagent scope audit: PASS.

The final pushed packet attachment SHA is intentionally reported out-of-band.

## 9. Failures And Unrun Work

- sandbox/cache retries: `swift test --package-path Packages/DesignSystem` first failed in the default sandbox because SwiftPM/clang user cache writes were blocked; the same command passed outside the sandbox.
- sandbox/TestReport retry: `xcrun xcresulttool get test-results tests --path <packet-validation-bundles> --compact` first failed in the default sandbox because `TestReport` temporary writes were blocked; the same fixed bundles parsed outside the sandbox.
- duplicate-class warning classification: simulator runs emitted duplicate-class warnings from app/test bundle linkage. These are environment warnings, not startup-network evidence. Plain `URLSession` duplicate-class warnings, if present in future local runs, are classified as environment noise only when all stronger startup-network tokens remain `0`.
- long E2E: not run.
- Maestro: not run.
- full `xcodebuild test`: not run.
- no upload/export telemetry validation was needed because this packet adds no telemetry, upload, export, CI, or file-writer path.

## 10. Self-SHA Rule

This file does not claim to contain the final commit SHA that adds it. The final pushed SHA must be verified after commit and push with:

- `git rev-parse HEAD`
- `git rev-parse origin/main`
- `git -c core.fsmonitor=false status --short --branch`
