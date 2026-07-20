# Home Timeline Sync Strategy

## Goal

Home TimelineのREQを起動、Realtime、pull-to-refresh、過去取得、gap解決、依存イベント解決に分離し、同じ目的のREQを重複発行しない。UIデザインとviewportのanchor規則は変更しない。

## Invariants

- NIP-65のwrite relayは候補であり、同一authorの全イベントが全relayへ複製されているとは仮定しない。
- Realtimeのforward REQは接続中に維持し、pull-to-refreshでは再生成しない。
- 起動時はDBにある最新kind:3/kind:10002をseedとして直ちに利用し、remote結果はfreshness規則で統合する。
- Full OutboxのREQはauthorと無関係なrelayへ送らない。`all authors x all relays`のcross-productを禁止する。
- backward timeout/CLOSEDは「未確認」であり、「履歴が存在しない」または`hasMoreOlder = false`の根拠にしない。
- 後着イベントはevent IDでdedupeし、既存のviewport anchorより上へ挿入して画面位置を変えない。
- event ID指定解決は、候補relayのいずれかで見つかった時点で完了できる。

## Request Ownership

1. 起動時bootstrap
   - DBの最新kind:3/kind:10002をseedとしてrelay/followを決定する。
   - remote kind:3/kind:10002はseedの更新確認であり、空応答でseedを消さない。
   - Full Outbox時のfollow先kind:10002もDBの既知値を先に使う。

2. Realtime
   - `HomeTimelineRelayRuntimeConfigurator`だけがforward REQを所有する。
   - 設定、follow、relay routing、feed revisionが変わった場合だけ置換する。
   - EOSE後もsubscriptionを維持し、同一構成の再installを行わない。

3. Pull-to-refresh
   - relayから既に受信してbufferされているイベントをprojectionへ適用するだけにする。
   - forward REQのCLOSE、再接続、再install、kind:3/kind:10002再解決を行わない。
   - 同時実行は1件に直列化する。

4. Full Outbox backward / gap
   - `author -> candidate relays`を次の優先順で構成する。
     1. そのauthorのイベントを実際に受信したrelay
     2. NIP-65 write relay
     3. kind:3 relay hint
     4. Home relay fallback
   - 各authorのprimary candidateだけを第1段REQへ入れる。
   - 第1段の結果がpage limit未満、partial、timeout、CLOSEDの場合だけ残りのcandidateへhedged REQを発行する。
   - coverageは`author x candidate relay x time range`として扱う。単一relayのEOSEをauthor全体の完了としない。
   - gapの正確な検証はcandidate relayに対するNegentropyまたは同等の集合差分で行う。
   - `hasMoreOlder = false`は、関連candidate scopeが正常に枯渇した場合だけ確定する。

5. Profile / referenced event dependencies
   - nevent/nprofile等の明示relay hintを最優先する。
   - hint relayはTemporary Relayとして必要時だけ接続し、該当REQ完了後にforward需要がなければ解放する。
   - 同じdependency keyのpending/TTLを共有して重複REQを抑止する。

## Delivery Order

1. seed bootstrapとfreshness統合
2. Realtime/pull-to-refreshの所有権確認と再install抑止
3. candidate routingモデルと受信実績query
4. backward primary/hedge実行と完了判定
5. dependency hint/Temporary Relay回帰テスト
6. package test、app test、Xcode build

## Non-goals

- Timelineの見た目、cell layout、scroll UIを変更しない。
- NIP-65のrelay listを永続的な到達保証として扱わない。
- 1回の変更でNegentropy transport自体を置換しない。coverage境界を先に確立する。
