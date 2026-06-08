# XcodeGen Local Package Boundaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** XcodeGen + Local Swift Package 構成を、`AstrenzaCore` を軸にした明確な依存境界と一括テスト可能なschemeへ安定化する。

**Architecture:** App target はUI/App stateだけを直接持ち、DB/署名/Negentropyなどの低レベル実装は `AstrenzaCore` package 経由に寄せる。今回は大規模Feature分割は行わず、`project.yml` のscheme/依存を現在のimport実態と一致させ、次に切るべきLocal Package候補を文書化する。

**Tech Stack:** XcodeGen 2.45.4, SwiftPM Local Package, Swift 6.1, iOS 26, `AstrenzaCore`, GRDB, secp256k1.swift, negentropy-swift.

---

## 現状確認

- `project.yml` は `AstrenzaCore` を `Packages/AstrenzaCore` のLocal Packageとして参照している。
- `Astrenza/Sources` 内で直接importされている外部Packageは `AstrenzaCore` のみ。
- `Astrenza/Tests/AstrenzaTests/NostrTimelineSyncTests.swift` は `secp256k1` を直接importしている。
- `Astrenza/Tests` 内で `GRDB` を直接importしているファイルはない。
- `Packages/AstrenzaCore` は `GRDB`, `secp256k1`, `Negentropy` を直接使っている。
- `Astrenza` scheme は現在 `AstrenzaTests` だけを実行対象にしており、`AstrenzaCoreTests` はschemeから一括実行されない。

## Files

- Modify: `project.yml`
  - `Astrenza` target から未使用の直接依存 `GRDB.swift`, `secp256k1`, `negentropy-swift` を外す。
  - `AstrenzaTests` target から未使用の直接依存 `GRDB.swift` を外す。
  - top-level `schemes.Astrenza.test.targets` を定義し、`AstrenzaTests` と `AstrenzaCore/AstrenzaCoreTests` を実行対象にする。
- Create: `Documents/Plans/2026-06-08-xcodegen-local-package-boundaries.md`
  - 今回の実装計画と次段階のPackage分割候補を保存する。

## Task 1: project.yml のschemeと依存を整理する

- [x] **Step 1: `project.yml` の `Astrenza` target dependencies を最小化する**

変更前:

```yaml
    dependencies:
      - package: AstrenzaCore
        product: AstrenzaCore
      - package: GRDB.swift
        product: GRDB
      - package: secp256k1
        product: secp256k1
      - package: negentropy-swift
        product: Negentropy
```

変更後:

```yaml
    dependencies:
      - package: AstrenzaCore
        product: AstrenzaCore
```

- [x] **Step 2: `AstrenzaTests` target dependencies から未使用GRDBを外す**

変更後:

```yaml
    dependencies:
      - target: Astrenza
      - package: AstrenzaCore
        product: AstrenzaCore
      - package: secp256k1
        product: secp256k1
```

- [x] **Step 3: top-level schemeへApp testsとCore package testsを登録する**

`project.yml` 末尾に追加する:

```yaml
schemes:
  Astrenza:
    build:
      targets:
        Astrenza: all
        AstrenzaTests: [test]
    test:
      targets:
        - AstrenzaTests
        - package: AstrenzaCore/AstrenzaCoreTests
```

- [x] **Step 4: XcodeGenでprojectを再生成する**

Run:

```bash
xcodegen generate
```

Expected:

```text
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at ...
```

## Task 2: 検証する

- [x] **Step 1: App buildを確認する**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [x] **Step 2: App testsを確認する**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/HomeTimelineUnreadStateTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [x] **Step 3: Core package testsを確認する**

Run:

```bash
swift test --package-path Packages/AstrenzaCore
```

Expected:

```text
Build complete!
Test Suite 'All tests' passed
```

- [x] **Step 4: schemeからCore package testが見えるか確認する**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -showTestPlans
```

Expected:

`Astrenza` scheme が解決でき、scheme関連のエラーが出ない。`-showTestPlans` が空でも、scheme解決エラーがなければこのTaskでは合格とする。

## Task 3: 次段階のLocal Package候補を確定する

- [x] **Step 1: 次に切るPackage候補をこの計画に記録する**

次段階候補:

```text
1. AstrenzaTimelinePresentation
   - 候補: TimelineModels, NostrTimeline*Projection, TimelineRestoreModels
   - 目的: event JSON -> TimelinePost / TimelineMedia / RichContent の変換をUIから分離する
   - まだ切らない理由: SwiftUI Color / AvatarStyle / View表示モデルとの結合が残っている

2. AstrenzaTimelineUI
   - 候補: Components/Timeline
   - 目的: Post Row / Media / OGP / Detail UIを独立プレビュー・テストしやすくする
   - まだ切らない理由: HomeTimelineView, navigation, action menu, shared themeとの結合が残っている

3. AstrenzaSettingsUI
   - 候補: Components/Settings, Components/Relay
   - 目的: relay/filter/list settingsをHome TLから独立させる
   - まだ切らない理由: sessionStore / liveTimelineStore / relay status DBへの依存境界整理が先
```

## Task 4: Commit

- [x] **Step 1: 差分確認**

Run:

```bash
git diff --stat
git diff -- project.yml Documents/Plans/2026-06-08-xcodegen-local-package-boundaries.md
```

Expected:

`project.yml` と計画ファイルだけに差分がある。`xcodegen generate` による `.xcodeproj` 差分が出る場合は、生成物として同じcommitに含める。

- [x] **Step 2: atomic commit**

Run:

```bash
git add project.yml Astrenza.xcodeproj Documents/Plans/2026-06-08-xcodegen-local-package-boundaries.md
git commit -m "Stabilize XcodeGen package boundaries"
```

Expected:

```text
[main <hash>] Stabilize XcodeGen package boundaries
```

## Completion Criteria

- `Documents/Plans/2026-06-08-xcodegen-local-package-boundaries.md` が存在する。
- `project.yml` の `Astrenza` target は `AstrenzaCore` のみへ直接依存する。
- `project.yml` の `AstrenzaTests` target は `GRDB` へ直接依存しない。
- `project.yml` の `Astrenza` scheme は `AstrenzaTests` と `AstrenzaCore/AstrenzaCoreTests` をtest targetに含む。
- `xcodegen generate` が成功する。
- `xcodebuild ... build` が成功する。
- `xcodebuild ... test -only-testing:AstrenzaTests/HomeTimelineUnreadStateTests` が成功する。
- `swift test --package-path Packages/AstrenzaCore` が成功する。
- atomic commitが作成される。
