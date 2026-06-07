# Persistent Relay Runtime Migration Plan

Date: 2026-06-07

## Goal

Move Astrenza's Nostr transport from short-lived WebSocket fetches toward a persistent relay runtime inspired by rx-nostr's forward/backward REQ model.

The target state is:

- Home TL uses a long-lived forward REQ.
- Home TL does not close the subscription on EOSE.
- Events received after EOSE are verified, persisted to GRDB, materialized, and incrementally rendered.
- kind:0, reply parents, repost sources, quoted repost sources, media metadata, and OGP work use backward REQ queues.
- Both forward and backward REQ paths support automatic batching and chunking.
- Relay liveness, reconnect, suspension, Relay Pill, and Relay Status Sheet are based on runtime state plus DB history.
- Existing mock routes and tests remain available while the real runtime is introduced.

## rx-nostr Concepts To Preserve

### Default Relays

Default read relays are long-lived connection targets. A relay configuration change should reconfigure active subscriptions:

- Removed read relay: CLOSE active REQs on that relay and disconnect when no longer needed.
- Added read relay: connect and issue equivalent active forward REQs.

Temporary relays may still be short-lived later, but Home TL read relays must not open and close per request.

### Forward REQ

Forward REQ is for future events:

- Stable subId per logical stream.
- At most one active subscription per stream per relay.
- EOSE is a catch-up marker, not a close trigger.
- The subscription remains open after EOSE.
- Reconnect reissues active forward REQs.
- Lazy `since` is used on reconnect so the reissued filter starts from the newest persisted event plus a small overlap.

Home TL should be a forward REQ:

- Initial filter: followed authors, `kinds: [1]`, bounded by current cursor.
- After EOSE: keep the same subscription open.
- New EVENT messages are saved and observed from DB.

### Backward REQ

Backward REQ is for historical or on-demand data:

- Unique subId per request packet.
- Multiple backward REQs may run concurrently.
- CLOSE on EOSE.
- CLOSE on idle timeout when no EVENT arrives for a configured interval.
- CLOSE on non-AUTH CLOSED.
- Supports an `over()`-like completion concept for grouped work.

Backward REQ should power:

- kind:0 profile resolution.
- NIP-05 related profile refresh inputs where applicable.
- reply parent/source event fetches.
- repost and quoted repost source fetches.
- deleted/tombstone source reconciliation.
- media metadata and OGP supporting event fetches.
- gap fill and older pagination.

### Batch

Batch merges short bursts of logically compatible ReqPackets:

- kind:0 queue merges authors.
- event source queue merges ids.
- media/OGP support queue merges ids or urls after normalization where applicable.
- Default batch window: 250 ms for UI-triggered dependencies, 1000 ms for background expansion.
- Deduplicate ids/authors before sending.

### Chunk

Chunk splits oversized REQs:

- Respect NIP-11 `limitation.max_subscriptions` for concurrent subscriptions.
- Also impose local filter size limits:
  - ids per filter: 250 initial local default.
  - authors per filter: 250 initial local default.
  - filters per REQ: min(NIP-11 max_filters if known, local default 100).
- Chunking must preserve request group identity so completion can be tracked across chunks.

### Auto Filtering

All incoming events must be filtered before DB write:

- Verify event id and signature.
- Validate filter matching except for fields with no standard interpretation such as `search`.
- Apply NIP-40 expiration filtering.
- Dedupe by event id.

## Proposed Architecture

```text
NostrRelayRuntime
  RelayRegistry
  RelaySession actor per relay
  ForwardREQManager
  BackwardREQScheduler
  RelayRuntimeEventSink
  RelayRuntimeStateStore

RelaySession
  URLSessionWebSocketTask
  connection state
  active subscriptions
  outbound queue
  heartbeat
  reconnect/backoff

ForwardREQManager
  home timeline stream
  stable subId
  lazy filter builder
  reconnect restore

BackwardREQScheduler
  request queues by purpose
  batch windows
  chunk policy
  completion tracking
```

## Runtime State

Each relay session tracks in memory:

- `initialized`
- `connecting`
- `connected`
- `waitingForRetry`
- `retrying`
- `dormant`
- `error`
- `rejected`
- `suspended`
- `terminated`

DB sync history continues to store durable events:

- `connected`
- `eose`
- `closed`
- `reconnect`
- `timeout`
- `partialFailure`
- `authRequired`
- `paymentRequired`
- `negentropy`

Additions to consider after the first runtime slice:

- `heartbeat`
- `suspended`
- `rejected`

## Liveness And Reconnect Policy

Home TL read relays should remain connected while the in-memory session is active.

Heartbeat:

- If any inbound message arrived recently, do nothing.
- If no inbound message arrived for 60 seconds, send WebSocket ping.
- If ping is unavailable or inconclusive, send a lightweight fallback REQ with a valid impossible id and `limit: 1`.
- Heartbeat success updates runtime state and can write a low-noise DB event later if needed.

Reconnect:

- On unexpected WebSocket close, network error, ping timeout, or repeated send failure, mark relay as `waitingForRetry`.
- Use linear backoff with jitter for MVP:
  - 5s, 15s, 30s, 60s, 120s.
- After max attempts, mark the relay `suspended` for the current in-memory app session.
- Do not retry-loop on `authRequired` or `paymentRequired`; those become blocked states.
- Clear `suspended` on foreground resume, explicit user retry, relay settings save, or account switch.

## Home TL Flow

1. Account login resolves NIP-65 relay list.
2. Runtime sets default read relays.
3. Runtime opens persistent relay sessions.
4. Home forward REQ is installed on all readable active relays.
5. EOSE writes sync history and marks initial catch-up complete.
6. Subscription remains open.
7. EVENT after EOSE:
   - parse
   - verify
   - validate filter match
   - save event
   - update sync cursors
   - enqueue dependent backward work
   - DB observation refreshes timeline rows

## Dependency Fetch Flow

When a timeline event is saved:

1. Extract unknown profile authors.
2. Extract reply/repost/quote source ids.
3. Extract media metadata dependencies.
4. Extract OGP candidates.
5. Enqueue purpose-specific backward work.
6. Batch and dedupe.
7. Chunk by policy.
8. Issue backward REQs on selected relays.
9. On EOSE or idle timeout, close chunk subscription.
10. Persist received events.
11. Re-materialize affected timeline rows.

## Phase Plan

### Phase 1: Runtime Model And Scheduler Tests

Deliverables:

- Add core runtime model types without connecting them to UI yet.
- Add `RelayConnectionState`.
- Add `NostrSubscriptionStrategy` with `.forward` and `.backward`.
- Add `NostrREQPacket`.
- Add batch helpers for authors and ids.
- Add chunk helpers for authors, ids, and filters.
- Add Swift Testing coverage.

Verification:

- Swift package tests pass.
- Batch dedupes authors and ids.
- Chunk preserves all ids/authors without duplication.
- Forward packet keeps stable subId.
- Backward packet can produce unique subIds.

### Phase 2: RelaySession Actor Skeleton

Deliverables:

- Add `NostrRelaySession` actor.
- Own one WebSocket task per relay.
- Maintain runtime state.
- Send REQ/CLOSE frames.
- Receive messages and emit parsed packets through an async stream.
- Do not replace existing short-lived fetch yet.

Verification:

- Unit tests with a fake transport.
- State transitions cover connect, connected, closed, retry waiting, suspended.

### Phase 3: Forward Home TL Runtime

Deliverables:

- Add `NostrHomeTimelineRuntimeStore` or extend existing store behind a feature boundary.
- Open Home TL forward subscriptions through runtime.
- Keep subscriptions after EOSE.
- Persist post-EOSE events.
- Relay Pill reads runtime state plus DB history.

Verification:

- Fake relay test proves EOSE does not close the forward subscription.
- Fake relay test proves an EVENT after EOSE is saved.
- UI model test proves Relay Pill reports runtime connected/planned accurately.

### Phase 4: Backward Dependency Scheduler

Deliverables:

- kind:0 queue.
- source event queue for reply/repost/quote.
- batch and chunk policies wired into scheduler.
- DB save and materialization refresh hooks.

Verification:

- A burst of timeline events creates one batched kind:0 request per chunk.
- quoted repost source id resolves through backward queue.
- reply parent resolves through backward queue.

### Phase 5: Liveness And Reconnect

Deliverables:

- Heartbeat loop.
- Linear backoff with jitter.
- in-memory suspended state.
- Runtime state sheet data.
- DB history for important state transitions.

Verification:

- Consecutive heartbeat failures transition to retry and then suspended.
- `authRequired` and `paymentRequired` do not retry-loop.
- Relay Status Sheet displays runtime state and history.

### Phase 6: Replace Short-Lived Home Fetch

Deliverables:

- Home TL real route uses runtime by default.
- Existing loader remains only for bootstrap fallback or tests.
- Maestro mock route remains isolated.

Verification:

- Swift package tests pass.
- iOS tests pass.
- Simulator smoke test shows Home TL and Relay Pill.

## Risks

- SwiftUI observation can over-render if DB writes are too granular.
- Relay limits vary widely; chunk defaults must be conservative.
- Reconnect can duplicate events; DB idempotency must remain strict.
- EOSE latency and live connection state are related but not equivalent.
- A persistent runtime changes lifecycle assumptions in tests.

## Non-Goals For First Runtime Slice

- Publishing pipeline replacement.
- NIP-42 AUTH signing flow beyond state classification.
- NIP-77 negentropy runtime integration.
- Temporary relay optimization.
- Full media download pipeline rewrite.

