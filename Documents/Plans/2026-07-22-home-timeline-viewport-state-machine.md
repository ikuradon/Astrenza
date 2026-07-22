# Home Timeline viewport state machine

## Goal

Home Timelineのスクロール位置、LIVE追従、起動同期、未表示スタック、
pull-to-refresh、Gap補完を、互いに独立したBooleanではなく単一の状態遷移で
決定する。既存デザインは変更しない。

## Authoritative inputs

- UICollectionViewが現在適用済みの先頭post ID
- anchor line上に実際に表示されているpost ID
- content startにいるか
- UICollectionViewへ適用済みのsource revision
- ユーザーの縦スクロール操作中か
- restore / pull-to-refresh transaction
- Home forward subscriptionがEOSE後のrealtime状態か
- 未表示スタック件数

SwiftUIの推測したoffsetだけではLIVEを決定しない。

## Modes

- `restoring`: 保存anchorを復元中。新しいRowを追従せず、位置保存もしない。
- `refreshing`: pull-to-refresh開始から、更新revisionがUICollectionViewへ反映されるまで。
- `browsing`: 過去閲覧、ユーザー操作中、pendingあり、または実先頭と投影先頭が不一致。
- `head`: 実先頭を表示しているがforward subscriptionがrealtime前。
- `live`: pendingがなく、操作中でなく、実先頭を表示し、forward subscriptionがrealtime。

`isAtNewestWindow`は`head`または`live`だけ、LIVEアイコンとsnapshotの
`followNewest`許可は`live`だけから導出する。

## Transitions

1. 起動・restore
   - restore完了までは`restoring`。
   - catch-up eventは表示listへ入れるが`followNewest`しない。
   - snapshot適用時は表示anchorを保存する。
   - 実先頭と投影先頭が一致し、EOSE後なら初めて`live`へ遷移する。
2. ユーザースクロール
   - drag開始時点で`browsing`へ遷移する。
   - 以後のrealtime eventはpendingへ積む。
   - drag終了後もpendingがある限り`live`へ戻らない。
3. pull-to-refresh
   - trigger時の表示anchorをtransaction anchorにする。
   - REQを再生成せず、pendingを最新projectionへ反映する。
   - 最新windowは現在windowへanchor中心でマージする。
   - 更新revisionがUICollectionViewへ反映されるまで`refreshing`を維持する。
   - snapshotはtransaction anchorを保存するため、表示Rowは動かない。
4. LIVE
   - `live`時だけprepend snapshotを先頭へ追従する。
   - LIVE時は未読pillを表示しない。
   - 横スワイプはviewport stateを変更しない。
5. Gap / older load
   - どちらもLIVE追従を許可せず、表示anchorを保存する。
   - Gap方向はviewportに対する上下で決定し、一つのGapにつき一つだけ実行する。

## Acceptance tests

- offsetが0でもpendingがあればLIVEにならない。
- 実先頭Row IDと投影先頭Row IDが違えばLIVEにならない。
- drag開始だけでLIVEを離れ、drag中のeventはpendingになる。
- startup catch-up prependは表示anchorを保存する。
- pull-to-refreshは元の表示anchorを保存し、pending適用後も自動で先頭へ飛ばない。
- 更新revisionがUICollectionViewへ適用される前にrefreshingを終了しない。
- LIVE prependだけが先頭へ追従する。
- LIVEと未読pillを同時表示しない。
