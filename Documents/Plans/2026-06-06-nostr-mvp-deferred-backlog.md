# Nostr MVP Deferred Backlog

This backlog records Research-derived items that are intentionally deferred from the Home TL MVP completion plan.

## Filter, Mute, Bookmark, and Trust

- Add an active filter indicator with one-tap clear.
  - Current state: materialized posts can be collapsed as `Filtered`.
  - Next step: show a compact indicator only when a temporary timeline filter is active, without changing stored source events.
- Publish bookmark changes as NIP-51 bookmark sets after outbox publish UX is ready.
  - Current state: local bookmark storage exists and the row gear menu can write local bookmarks.
  - Next step: bridge local bookmark actions to replaceable `kind:30003` events through the persistent outbox.
- Publish mute changes as NIP-51 mute lists after signer-backed replaceable list editing is ready.
  - Current state: cached public NIP-51 mute-list items are projected into `NostrFilterRuleSet`, and local mute rules are applied immediately.
  - Next step: bridge local mute rule edits to `kind:10000` replaceable events through the persistent outbox.

## Lists and Timeline Modes

- Promote NIP-51 follow sets, relay sets, bookmark sets, and search relays to first-class timeline selectors.
  - Current state: addressable/list storage exists.
  - Next step: add list timeline UI after Home TL real-data flow is stable.
- Add list exclusion and home composition controls.
  - Current state: not required for MVP Home TL.
  - Next step: model as account-scoped timeline policy, not as event deletion.

## Moderation and Trust

- Add full report/mute UI wiring for temporary mute expiry, regex validation, and private mute items.
  - Current state: local rule schema supports expiry and regex matching, and the row gear menu can create author mutes.
  - Next step: settings and action menu surfaces should create/update rules.
- Add richer relay privacy explanation.
  - Current state: relay state/settings screens exist.
  - Next step: explain which relay receives read/write filters and account metadata.

## Post and Media Expansion

- Add richer non-`kind:1` rendering beyond MVP rows.
  - Current state: deletion, expiration, sensitive content, media, OGP, repost, quote, and reply materialization are covered for Home TL basics.
  - Next step: expand long-form, highlights, video, community, and DVM events only after core Home TL is reliable.
- Add NIP-92 `imeta` editing/publish flow.
  - Current state: media materialization can read stored media records.
  - Next step: compose/upload pipeline should write `imeta` and alt text consistently.
