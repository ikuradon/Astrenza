# Timeline Diagnostics Artifact Contract

Status: restore gate diagnostics artifact の active contract
Scope: `TimelineDiagnosticsExport` JSON、offline fixture consumer、debug/failure artifact
Source references:
- `Documents/Specifications/astrenza_nostr_client_development_spec.md`
- `Astrenza/Sources/AstrenzaApp/TimelineEngine/TimelineDiagnosticsRecorder.swift`
- `Astrenza/Tests/AstrenzaTests/TimelineRestoreGateBudgetTests.swift`

## Purpose

`TimelineDiagnosticsExport` は local/debug/failure-artifact data のみである。Timeline restore gate の挙動を tests、fixture consumer、local debug tooling、将来の CI failure artifact から検査できるようにするために存在する。

この export は product telemetry ではない。将来の privacy decision が明示的に許可しない限り、upload、sync、analytics への添付、remote logging 送信、外部 service への送信をしてはいけない。

artifact contract は production Home または production Timeline runtime wiring が存在しない状態でも使える必要がある。offline tests と fixture consumer は、Home launch、DB open、relay sync start、network work なしに DTO を decode し、`summary.restoreGateMetrics` を読める必要がある。

## Privacy Prohibitions

`TimelineDiagnosticsExport` とそこから生成される JSON には、次の情報を含めてはいけない。

- `nsec`、secret key、signing material、NIP-46 secret、auth token、bearer token。
- raw event JSON、raw private content、復号済み private message、private relay/account material。
- raw account configuration、private relay list、writable relay credential、Keychain data、signing payload。
- 上記を埋め込んだ crash/log string。

将来の CI job がこの JSON を failure artifact として保存する場合、その job は上記の禁止 material に対する privacy check を先に通す必要がある。privacy check は artifact upload より前に実行する。

この privacy check は repository 全体や docs ではなく、生成済みの diagnostics artifact JSON だけに対して実行する。

```bash
scripts/guard_timeline_diagnostics_artifact.sh <path-to-timeline-diagnostics-export.json>
```

directory を渡す場合、この guard は配下の `*.json` だけを検査する。fixture または CI job を追加する前には、guard 自体の safe/unsafe behavior も確認できる。

```bash
scripts/guard_timeline_diagnostics_artifact.sh --self-test
```

## Allowed Consumers

現在許可される consumer:

- offline unit tests。
- fixture-backed JSON shape tests。
- offline artifact-summary consumers。
- local debug inspection。

将来許可される consumer:

- DTO または `summary.restoreGateMetrics` を読む debug screen。
- 上記の privacy check を通した後の CI/failure-artifact reader。

禁止される consumer behavior:

- artifact を読むだけで DB query、relay startup、network request、media/profile/OGP resolve、account restore、production Home/Timeline runtime wiring を trigger してはいけない。
- debug screen は decoded artifact の値を表示してよいが、artifact read path を live DB/network state に依存させてはいけない。

## Restore Gate Summary Fields

release-facing summary path は次の通り。

```text
TimelineDiagnosticsExport.summary.restoreGateMetrics
```

artifact contract では、offline consumer が次の fields を読めることを要求する。

| Field | Meaning |
|---|---|
| `totalAttempts` | 記録された restore gate diagnostic attempt 数。 |
| `withinBudgetCount` | aggregate restore gate budget result が `withinBudget` の attempt 数。 |
| `overTargetCount` | target duration を超えたが hard limit 以内だった attempt 数。 |
| `exceededBudgetCount` | 1 つ以上の hard budget limit を超えた attempt 数。 |
| `releaseBlockingCount` | release-blocking な restore gate behavior を含む attempt 数。 |
| `networkWaitedBeforeInteractiveScrollViolationCount` | `networkWaitedBeforeInteractiveScrollMS > 0` の attempt 数。 |
| `maxRestoreGateDurationMS` | 記録された `.restoreGate` duration の最大値。 |
| `maxLocalInitialWindowQueryMS` | 記録された `.localInitialWindowQuery` duration の最大値。 |
| `maxInitialSnapshotApplyMS` | 記録された `.initialSnapshotApplying` duration の最大値。 |
| `maxAnchorRestoreMS` | 記録された `.anchorRestoring` duration の最大値。 |
| `maxNetworkWaitedBeforeInteractiveScrollMS` | first interactive scroll 前の network wait 最大値。 |
| `latestFallbackReason` | 最新の exceeded restore gate fallback reason。存在しない場合は nil。 |

現在の DTO は `readMarkerChanged`、`continuesSplash`、`requiresNetworkWork`、`requiresDBWork` のような guard boolean も持つ。offline fixture artifact では、violation を明示的に検証する test 以外でこれらを false に保つ。

## Release-Blocking Semantics

`networkWaitedBeforeInteractiveScrollMS > 0` は release-blocking である。first interactive Timeline scroll の期待値は network wait ちょうど `0ms` である。

`readMarkerChanged` は default `false` でなければならない。launch、root shell display、restore gate release、relay sync、EOSE、foreground、resolve work は `readMarkerChanged` を set してはならず、read marker を進めてもいけない。`readMarkerChanged == true` の restore gate artifact は release-blocking であり、read-state violation として調査する。

budget over-target value は diagnostic warning になり得るが、hard-limit exceedance と fallback reason は artifact summary から見える必要がある。artifact は少なくとも次を区別できる data を保持する。

- `withinBudget`
- `overTarget`
- `exceededBudget`
- first interactive scroll 前の network wait
- restore 中の read marker mutation
- splash continuation ではない inline fallback

## Runtime Boundaries

この export は DTO/failure artifact boundary であり、production integration point ではない。`TimelineDiagnosticsExport` の追加や読み取りは、次を行ってはいけない。

- `TimelineEngine` を production Home へ wire する。
- legacy SwiftUI Timeline path を extend する。
- relay/network work を start する。
- SQL schema change を要求する。
- dependency を追加する。
- debug screen UI を単独で実装する。
- `ResolveCoordinator` を実装する。

将来の production Timeline code は diagnostics を記録してよい。ただし JSON artifact 自体は production Home/Timeline runtime wiring なしで decode と summary 生成ができる状態を維持する。

## Validation Expectations

この artifact contract を変える docs または code change では、次を含める。

- DesignSystem または new Timeline path を触る場合の `scripts/guard_designsystem.sh`。
- diagnostics export JSON shape、fixture path、failure-artifact upload path、または artifact privacy boundary を触る場合の `scripts/guard_timeline_diagnostics_artifact.sh <path-to-json-or-dir>`。
- `git diff --check`.
- current v1 baseline としての `swift test --package-path Packages/DesignSystem`。
- DTO shape、summary aggregation、restore gate release-blocking behavior を変える場合の targeted `xcodebuild test` for `AstrenzaTests/TimelineRestoreGateBudgetTests`。
- docs-only task の場合、production code、legacy Timeline files、Home/root/splash、`TimelinePlaceholderRow`、SQL schema が変更されていないことを示す targeted `git diff --name-only` checks。
