# AGENTS.md

この repository で作業する Codex agent への必須指示です。

## Communication

- ユーザーへの説明、進捗報告、最終回答は日本語で書く。
- 技術用語、code identifier、file path、command、API 名は原文のまま扱う。
- ライブラリ、framework、SDK、API、CLI、cloud service の使い方や設定を調べる場合は、推測で答えず `ctx7` CLI を使う。`npx ctx7@latest library <name> "<question>"` で ID を解決してから `npx ctx7@latest docs <libraryId> "<question>"` を実行する。secret を query に含めない。

## Workflow

- 編集前に context gathering を行い、`git status --short --branch` と関連ファイルを確認する。
- Superpowers workflow、または同等の planning / todo / checkpoint / review workflow を使う。
- 実装前に明示的な小さい計画を立て、変更範囲を狭く保つ。
- 既存の user change を勝手に戻さない。破壊的な git 操作はユーザーの明示依頼なしに行わない。
- すべての変更に test または documented best-effort validation を付ける。

## Source Of Truth

- `Documents/Specifications/astrenza_nostr_client_development_spec.md` を Astrenza v1 の canonical source of truth とする。
- `Documents/Specifications/README.md`、`Documents/Specifications/astrenza_local_db_schema_v0_2.sql`、`Documents/Specifications/astrenza_local_db_schema_v0_2_migration.sql` は supporting source-of-truth とする。
- `Documents/Specifications/Archive/` は archived reference only。履歴や失敗理由の確認にだけ使う。
- v1 spec と Archive の `v0.4` または legacy review が違う場合、必ず v1 spec を優先する。Archive から直接実装しない。

## Salvage Policy

- project 全体を捨てない。
- `AstrenzaCore`、GRDB/SQLite 方向、Nostr event store 方向、projection tests、relay planner/diagnostics、media resolver、Maestro intent、useful fixtures は、spec-backed migration がない限り保持・移植候補として扱う。
- Core/DB/projection/resolver/test assets を削除または置換する場合は、canonical spec に基づく移行理由、test plan、rollback/fixture 方針を残す。

## Timeline Guardrails

- legacy SwiftUI timeline を production-extend しない。
- 特に `TimelineFeedView`、`TimelinePostRow`、`TimelineAttachments`、およびそれらを支える `ScrollView` / `LazyVStack` timeline path に production behavior を追加しない。
- 新しい production Home / Mentions / Profile / Thread / List / Search timeline surface は `UICollectionView` + `UICollectionViewDiffableDataSource` + `UIHostingConfiguration` を使う。
- SwiftUI は app shell、navigation、settings、compose、detail chrome、row body には使ってよい。
- UIKit は production timeline の scroll engine、snapshot mutation、visible range、prefetch、anchor capture、anchor restore を所有する。
- Diffable snapshot item identity は stable `TimelineEntryID` / `feed_items.item_key` に限定する。profile、OGP、media、quote、reply parent などの resolve 状態を identity に含めない。
- Delayed resolve は row を enrich するだけで、row identity や visible anchor を変えない。原則 `reconfigureItems` 相当の更新を使い、delete/insert で解決済み表示へ差し替えない。
- `pending_new` はユーザー操作、またはユーザーが最上部にいる明示条件まで visible snapshot に自動挿入しない。
- read marker と scroll anchor を別の state として扱う。起動、root shell 表示、restore gate、relay sync、EOSE、OGP/media/profile/quote/reply resolve だけで read marker を進めない。
- network、relay、OGP、media、profile sync、search、maintenance は first interactive timeline restore をブロックしてはいけない。
- Launch Screen や app-wide splash で network/relay readiness を隠さない。許可されるのは timeline area 内の短い restore gate だけ。

## Design System

- DesignSystem tokens は runtime contract であり、任意の styling ではない。
- 新しい Timeline component では raw color、raw spacing、raw font size、ad-hoc icon size を使わない。
- action button は visual icon size と hit target を分け、44x44pt 以上の hit target を保つ。
- Timeline row height に影響する token 変更は snapshot / E2E anchor delta validation を要求する。
- DesignSystem または future Timeline component を変更した場合は `scripts/guard_designsystem.sh` を実行する。
- `Astrenza/Sources/AstrenzaApp/TimelineEngine`、`TimelineRows`、`TimelineV1` に追加する新しい Timeline code はこの guard に通す。
- `scripts/guard_designsystem.sh` は legacy SwiftUI Timeline を意図的に scan しない。Tokens、Timeline metrics、DesignSystem tests は baseline / expected 値のため allowlist される。

## Security

- `nsec`、secret key、signing material は DB、logs、crash output、analytics、test fixtures に入れない。
- secret を `debugDescription`、error message、fixture、screenshot、commit message に含めない。
- key/security まわりの変更は redaction test または documented manual audit を残す。
- `TimelineDiagnosticsExport` または diagnostics artifact JSON を変更する場合は `scripts/guard_timeline_diagnostics_artifact.sh <artifact.json-or-dir>` を実行する。この guard は生成済み artifact JSON 専用であり、repository 全体や docs を scan しない。

## Validation And Final Response

- 最終回答には必ず次を含める。
  - files changed
  - commands/tests run と結果
  - failures または未実行 test と理由
  - next recommended task
- test を実行していない場合は、通ったように書かない。
- commit する場合も、直前に fresh validation と `git status` を確認する。
