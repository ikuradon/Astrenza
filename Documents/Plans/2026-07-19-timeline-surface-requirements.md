# Timeline Surface 要件定義

## 1. 目的

AstrenzaのTimelineを、Tweetbot / Ivory系クライアントとして常用できる表示面にする。
本書はデザインを変更するための仕様ではなく、既存デザインを維持したまま、Row配置、
スクロール、更新、位置復元を壊さないための受け入れ条件を定義する。

今回の最優先事項は「速そうに見えること」ではなく、次の順で成立させることとする。

1. Row geometryの正しさ
2. viewportの連続性
3. 非同期更新時の安定性
4. スクロール性能

上位の条件を満たさない実装は、下位の数値が良くても採用しない。

## 2. 現行方式を不採用とする理由

現行実装はRow geometryに複数のauthorityが存在する。

- `TimelineFeedCollectionLayout`が推定値と永続cacheからCell frameを作る。
- `UIHostingConfiguration`はSwiftUI contentのintrinsic sizeを持つ。
- `TimelineFeedHostingCollectionCell`が`systemLayoutSizeFitting`で別途測定する。
- 測定結果を遅延してcustom layoutへ反映する。

この方式では、実際に描画されたcontent、Cell bounds、layout indexの高さが同一になる保証がない。
また、現行cache keyはpost IDだけであり、container width、Dynamic Type、locale、layout revisionを
区別できない。

したがって、次を不採用とする。

- SwiftUI Rowを表示後に測り、別のcustom indexへ高さを転記する方式
- 推定高と実測高をスクロール中または直後に差し替える方式
- overlapを`clipsToBounds`だけで隠す方式
- 実Cellを使わない算術testだけでRow安定性を合格とする方式

## 3. 用語

- **Row presentation**: 1投稿を描画するための不変な表示snapshot。
- **Geometry update**: Rowのheightまたは後続Rowのoriginを変える更新。
- **Paint-only update**: geometryを変えずにpixelだけを変える更新。
- **Anchor Row**: viewport内の基準線と交差する、位置保存対象の投稿。
- **Realtime follow**: 新着追加時にTimeline先頭へ追従するモード。
- **Scroll session**: drag開始からdeceleration終了まで。

## 4. 必須機能要件

### R-01 Row非重複

任意の隣接Rowについて、常に次を満たすこと。

```text
row[n].frame.maxY <= row[n + 1].frame.minY
```

表示内容、画像読込、プロフィール解決、relative time更新、snapshot更新、Cell reuseの途中を含め、
1 frameでもRow同士が重なってはならない。

### R-02 Row間隔の一意性

Row間のseparatorまたは余白は既存デザインで定義した値だけとする。推定高の残骸、reuse、
非同期測定による未知の空白を許可しない。

### R-03 Geometry authorityは一つ

Rowの測定と配置は同じlayout systemが所有すること。SwiftUIをRow rendererとして継続する場合は、
UIKitのself-sizing結果を唯一のauthorityとし、並行するheight index、永続実測cache、事後測定を持たない。

初期候補は`UICollectionView` + system self-sizing layout + `UIHostingConfiguration`とする。
ただし往復スクロールtestでcontent geometryが変動する場合は不採用とする。custom
`UICollectionViewLayout`を使用する場合は、表示CellのSwiftUI事後測定を禁止し、表示前に同じ
Row presentationを一度だけ測定して作った不変なgeometry indexを唯一のauthorityとする。

### R-04 Scroll session中のgeometry不変

Scroll session開始時点で存在するRowは、session終了までheightと相対originを変えない。
ユーザーが明示的に「展開」「折り畳み」を実行した場合だけ例外とする。

Scroll session中に到着したgeometry updateは保留し、session終了後に1つのtransactionとして適用する。

### R-05 非同期更新の分類

次はpaint-only updateであり、Row heightを変えてはならない。

- avatar画像の取得
- kind:0プロフィール解決
- NIP-05表示更新
- relative time更新
- reply/repost/favorite/zap状態と件数更新
- custom emoji画像の取得
- placeholderから実画像への置換

次はgeometry updateになり得る。

- bodyまたはrich textの内容変更
- content warningの開閉
- quote/reply contextの追加・削除
- media blockまたはlink preview blockの追加・削除
- ユーザーによる展開・折り畳み
- Dynamic Type、locale、container widthの変更

### R-06 Media geometry

一枚画像は元画像のaspect ratioを維持し、既存の最大高さを超えない。表示前にdimensionが不明な場合は、
安定したfallback geometryを採用する。画像decode完了だけを理由に表示中Rowのheightを変更しない。

複数画像、動画placeholder、OGPも、resource取得前後で外枠geometryを変えない。

### R-07 Snapshotの原子性

data sourceのitem順序とlayoutが参照するitem順序は、同じsnapshot transactionで切り替わること。
data source適用前に別のitem配列でlayout indexを再構築してはならない。

### R-08 デザイン維持

次を変更しない。

- typography、font size、weight
- avatar、body、attachment、action列の位置と余白
- separator、background、corner radius、color
- swipe/action menuの操作感
- Timelineを下部Tab Barの背面まで描画する構造

## 5. Viewport要件

### V-01 通常スクロール

ユーザー操作中は、Anchor Rowの画面上の位置をlayout更新で動かさない。

### V-02 起動・位置復元

保存されたAnchor Rowとoffsetを復元し、誤差は1 point以内とする。起動同期で新着が到着しても、
復元完了まではRealtime followしない。保存位置が先頭だった場合も同じである。

### V-03 Pull to refresh

refresh開始時のAnchor Rowを保持し、新着はその上へ挿入する。refresh前後でAnchor Rowの画面上の
位置を1 point以上動かさない。

### V-04 Realtime follow

新着へ自動追従してよいのは、次をすべて満たす場合だけとする。

- Realtime modeが有効
- 起動・復元中ではない
- Pull to refresh中ではない
- ユーザーが過去位置を閲覧していない
- 現在のviewportがnewest windowに接続されている

それ以外は新着をAnchor Rowより上へ積み、viewportを動かさない。

### V-05 未読Pill

Pillは「現在のAnchor Rowより上にある、投影済み未読投稿数」を表す。過去方向へスクロールした場合、
最後にcountしたAnchor Rowと一緒に上へ移動し、件数を減らさない。そのAnchor Rowへ戻った時点から
既読進行を再開する。

### V-06 位置保存

位置保存はユーザー操作後だけ行う。起動時の仮位置、snapshot適用中、programmatic scroll、
restore未完了状態を保存しない。

## 6. Performance要件

参照環境は現行deployment targetを動かす標準幅iPhoneとし、Debugだけで合否を決めない。

- 10,000 Rowのsnapshotを扱えること。
- 30秒の連続高速スクロールでcrash、hang、Row overlap、未知の空白が0件であること。
- main threadの100 ms以上のstallを0件にすること。
- 60 Hz端末で平均55 fps以上、hitch ratio 1%未満を目標とすること。
- profile/avatar/mediaの同時解決を注入しても、上記correctness gateを維持すること。

性能目標を満たせない場合、manual height cacheを再導入しない。次の選択肢はRow内部を
native UIKit/TextKitでdeterministic layoutへ移行することであり、geometry authorityを二重化しない。

## 7. Acceptance test要件

実装より先に、次のtest harnessを作る。

### A-01 実Cell geometry監視

Debug/UI test用に、表示中Cellを毎layout passで走査し、次を記録・assertする。

- 隣接Cell frameが重ならない
- 意図しないgapがない
- Cell contentがCell bounds外へ描画されない
- Scroll session中に同一IDのheightが変わらない

### A-02 非同期更新stress fixture

短文、長文、custom emoji、reply、quote、CW、一枚画像、複数画像、OGP、削除Row、gap Rowを混在させ、
スクロール中にavatar、profile、image、quote、relative time、action countを遅延解決する。

### A-03 Viewport fixture

次をID付きAnchor Rowの画面座標で検証する。

- cold start restore
- cached start restore
- 起動同期中のprepend
- Pull to refresh
- Realtime follow on/off
- 過去位置での新着受信
- 未読Pillの追従と再開

### A-04 Visual regression

既存デザインの代表Rowをsnapshot化し、surface置換前後で差分を確認する。geometry修正を理由に
padding、font、attachment sizeを変更しない。

### A-05 Performance計測

`XCTOSSignpostMetric`またはInstrumentsでscrolling/decelerationを計測する。単にアプリがforegroundで
終了したことだけでは合格にしない。

## 8. 実装方針

1. `b77cfcb`のRow Layout Projectionを撤去する。
2. overlapを再現するstress fixtureと実Cell assertionを先に追加する。
3. `TimelineFeedCollectionLayout`、`TimelineFeedLayoutIndex`、manual fitting、実測height cacheを
   active rendering pathから削除する。
4. system self-sizingの往復testが不合格なら、表示前に確定する不変なgeometry indexへ切り替える。
5. geometry fingerprintを導入し、paint-only updateとgeometry updateを分離する。
6. viewport、refresh、Realtime、restore、unread規則をAnchor Row transactionとして移植する。
7. 全acceptance testと実機相当performance gateを通した後に旧実装を削除する。

各段階をatomic commitにし、correctness gateに失敗したcommitの上へ補正を積まない。

### 8.1 検証後の採用設計

system self-sizingは、80 pointと320 pointのRowを交互に120件並べた往復scroll testで、操作前後の
`contentSize.height`が2,880 point変動したため不採用とした。原因は`estimatedItemSize`を使うFlow
Layoutが、画面外Rowを推定高で保持し、表示のたびに実測高へ置換する点にある。

採用するgeometry pipelineは次の通りとする。

1. snapshot適用前に、同じ`UIHostingConfiguration`からRow heightを決定する。
2. 全Rowのprefix sumを持つ不変な`TimelineFeedStableLayout`を構築する。
3. 表示Cellの`preferredLayoutAttributesFitting`では再採寸せず、layoutのframeをそのまま使う。
4. Scroll session中は既存Rowのheightを固定し、geometry updateはsession終了後にまとめる。
5. 適用時はAnchor Rowとoffsetを保存し、同じ画面座標へ復元する。
6. profile、avatar、relative time、action stateなどはgeometry fingerprintから除外する。

10,000件fixtureで発見した全投稿への`displayGapDirection`探索も廃止する。Gap以外からこの探索を
呼ばないことで、geometry projectionをO(n²)からO(n)へ戻す。

## 9. 完了条件

次をすべて満たした時だけTimeline surfaceの再構築を完了とする。

- R-01からR-08
- V-01からV-06
- Performance要件
- A-01からA-05
- 既存Unit test全件成功
- 実データTimelineで再現操作を行い、Row overlapが0件
- worktreeがcleanで、変更が段階別のatomic commitになっている
