-- Astrenza Nostr Client Local DB Schema v0.2
-- Target: SQLite via GRDB, Apple-first local-first client
-- Notes:
--   * Store Nostr IDs/pubkeys internally as 64-char lowercase hex TEXT for debuggability.
--   * npub/note/nevent/naddr are presentation formats only.
--   * raw event JSON is retained as the immutable source; projections are rebuildable.
--   * Foreign keys should be enabled by the application with PRAGMA foreign_keys = ON.

PRAGMA foreign_keys = ON;

BEGIN;

-- ============================================================
-- 1. Accounts / signer references
-- ============================================================
CREATE TABLE IF NOT EXISTS accounts (
  id                    INTEGER PRIMARY KEY,
  pubkey                TEXT NOT NULL UNIQUE CHECK (length(pubkey) = 64),
  display_name          TEXT,
  active                INTEGER NOT NULL DEFAULT 0 CHECK (active IN (0,1)),
  signer_type           TEXT NOT NULL DEFAULT 'local_keychain'
    CHECK (signer_type IN ('local_keychain','nip46_remote','readonly','external')),
  signer_ref            TEXT,
  created_at_ms         INTEGER NOT NULL,
  last_opened_at_ms     INTEGER,
  theme_json            TEXT NOT NULL DEFAULT '{}',
  client_state_json     TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS account_key_backups (
  account_id            INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  backup_type           TEXT NOT NULL CHECK (backup_type IN ('nip49_exported','manual_ack','remote_signer')),
  created_at_ms         INTEGER NOT NULL,
  metadata_json         TEXT NOT NULL DEFAULT '{}',
  PRIMARY KEY (account_id, backup_type)
);

-- ============================================================
-- 2. Relays / account relay preferences / NIP-11 state
-- ============================================================
CREATE TABLE IF NOT EXISTS relays (
  id                    INTEGER PRIMARY KEY,
  url                   TEXT NOT NULL UNIQUE,
  normalized_url        TEXT NOT NULL UNIQUE,
  read_enabled          INTEGER NOT NULL DEFAULT 1 CHECK (read_enabled IN (0,1)),
  write_enabled         INTEGER NOT NULL DEFAULT 1 CHECK (write_enabled IN (0,1)),
  user_configured       INTEGER NOT NULL DEFAULT 0 CHECK (user_configured IN (0,1)),
  last_connected_at_ms  INTEGER,
  last_error_at_ms      INTEGER,
  last_error            TEXT,
  avg_rtt_ms            INTEGER,
  health_score          REAL NOT NULL DEFAULT 0.0,
  supports_count        INTEGER CHECK (supports_count IN (0,1) OR supports_count IS NULL),
  supports_auth         INTEGER CHECK (supports_auth IN (0,1) OR supports_auth IS NULL),
  supports_negentropy   INTEGER CHECK (supports_negentropy IN (0,1) OR supports_negentropy IS NULL),
  nip11_json            TEXT,
  updated_at_ms         INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS account_relays (
  account_id            INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  relay_id              INTEGER NOT NULL REFERENCES relays(id) ON DELETE CASCADE,
  mode                  TEXT NOT NULL CHECK (mode IN ('read','write','both')),
  priority              INTEGER NOT NULL DEFAULT 100,
  source                TEXT NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual','nip65','default','observed','imported')),
  enabled               INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (account_id, relay_id, mode)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS relay_health_samples (
  id                    INTEGER PRIMARY KEY,
  relay_id              INTEGER NOT NULL REFERENCES relays(id) ON DELETE CASCADE,
  sampled_at_ms         INTEGER NOT NULL,
  event                 TEXT NOT NULL CHECK (event IN ('connect','disconnect','eose','ok_true','ok_false','closed','notice','timeout','auth_required')),
  rtt_ms                INTEGER,
  detail                TEXT
);

CREATE INDEX IF NOT EXISTS idx_relay_health_samples_relay_time
  ON relay_health_samples(relay_id, sampled_at_ms DESC);

-- ============================================================
-- 3. Immutable raw event store
-- ============================================================
CREATE TABLE IF NOT EXISTS events (
  id                    TEXT PRIMARY KEY CHECK (length(id) = 64),
  pubkey                TEXT NOT NULL CHECK (length(pubkey) = 64),
  created_at            INTEGER NOT NULL,
  kind                  INTEGER NOT NULL CHECK (kind BETWEEN 0 AND 65535),
  content               TEXT NOT NULL,
  tags_json             TEXT NOT NULL,
  sig                   TEXT NOT NULL CHECK (length(sig) = 128),
  raw_json              TEXT NOT NULL,

  is_valid              INTEGER NOT NULL DEFAULT 1 CHECK (is_valid IN (0,1)),
  validation_error      TEXT,
  expires_at            INTEGER,

  deleted_by_event_id   TEXT,
  deleted_at            INTEGER,
  local_hidden_reason   TEXT,

  first_seen_at_ms      INTEGER NOT NULL,
  last_seen_at_ms       INTEGER NOT NULL,
  seen_count            INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_events_kind_created
  ON events(kind, created_at DESC, id ASC);

CREATE INDEX IF NOT EXISTS idx_events_pubkey_kind_created
  ON events(pubkey, kind, created_at DESC, id ASC);

CREATE INDEX IF NOT EXISTS idx_events_pubkey_created
  ON events(pubkey, created_at DESC, id ASC);

CREATE INDEX IF NOT EXISTS idx_events_created
  ON events(created_at DESC, id ASC);

CREATE INDEX IF NOT EXISTS idx_events_expires
  ON events(expires_at) WHERE expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_events_deleted
  ON events(deleted_at) WHERE deleted_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS event_relays (
  event_id              TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  relay_id              INTEGER NOT NULL REFERENCES relays(id) ON DELETE CASCADE,
  first_seen_at_ms      INTEGER NOT NULL,
  last_seen_at_ms       INTEGER NOT NULL,
  seen_count            INTEGER NOT NULL DEFAULT 1,
  last_subscription     TEXT,
  PRIMARY KEY (event_id, relay_id)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_event_relays_relay_seen
  ON event_relays(relay_id, last_seen_at_ms DESC);

-- ============================================================
-- 4. Tags and references
-- ============================================================
CREATE TABLE IF NOT EXISTS event_tags (
  event_id              TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  tag_index             INTEGER NOT NULL,
  name                  TEXT NOT NULL,
  value                 TEXT,
  relay_url             TEXT,
  marker                TEXT,
  pubkey_hint           TEXT,
  extra_json            TEXT NOT NULL DEFAULT '[]',
  raw_json              TEXT NOT NULL,
  PRIMARY KEY (event_id, tag_index)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_event_tags_name_value
  ON event_tags(name, value, event_id);

CREATE INDEX IF NOT EXISTS idx_event_tags_value
  ON event_tags(value, event_id);

CREATE TABLE IF NOT EXISTS event_refs (
  event_id              TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  ref_type              TEXT NOT NULL,
  ref_value             TEXT NOT NULL,
  relay_url             TEXT,
  marker                TEXT,
  pubkey_hint           TEXT,
  target_kind           INTEGER,
  position              INTEGER NOT NULL,
  PRIMARY KEY (event_id, ref_type, position)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_event_refs_type_value
  ON event_refs(ref_type, ref_value, event_id);

CREATE INDEX IF NOT EXISTS idx_event_refs_value
  ON event_refs(ref_value, event_id);

-- ============================================================
-- 5. Replaceable/addressable heads
-- ============================================================
CREATE TABLE IF NOT EXISTS latest_replaceable_events (
  pubkey                TEXT NOT NULL CHECK (length(pubkey) = 64),
  kind                  INTEGER NOT NULL,
  d_tag                 TEXT NOT NULL DEFAULT '',
  event_id              TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  created_at            INTEGER NOT NULL,
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (pubkey, kind, d_tag)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_latest_replaceable_event
  ON latest_replaceable_events(event_id);

-- ============================================================
-- 6. Profile/follow/relay hints projections
-- ============================================================
CREATE TABLE IF NOT EXISTS profiles (
  pubkey                TEXT PRIMARY KEY CHECK (length(pubkey) = 64),
  name                  TEXT,
  display_name          TEXT,
  about                 TEXT,
  picture_url           TEXT,
  banner_url            TEXT,
  nip05                 TEXT,
  lud16                 TEXT,
  lud06                 TEXT,
  website               TEXT,
  metadata_event_id     TEXT REFERENCES events(id) ON DELETE SET NULL,
  metadata_created_at   INTEGER,
  raw_metadata_json     TEXT,
  updated_at_ms         INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_profiles_name
  ON profiles(name);

CREATE INDEX IF NOT EXISTS idx_profiles_nip05
  ON profiles(nip05);

CREATE TABLE IF NOT EXISTS follow_lists (
  owner_pubkey          TEXT NOT NULL CHECK (length(owner_pubkey) = 64),
  source_event_id       TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  created_at            INTEGER NOT NULL,
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (owner_pubkey)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS follows (
  owner_pubkey          TEXT NOT NULL CHECK (length(owner_pubkey) = 64),
  followed_pubkey       TEXT NOT NULL CHECK (length(followed_pubkey) = 64),
  relay_url             TEXT,
  petname               TEXT,
  position              INTEGER NOT NULL,
  source_event_id       TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (owner_pubkey, followed_pubkey)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_follows_followed
  ON follows(followed_pubkey);

CREATE TABLE IF NOT EXISTS author_relays (
  pubkey                TEXT NOT NULL CHECK (length(pubkey) = 64),
  relay_id              INTEGER NOT NULL REFERENCES relays(id) ON DELETE CASCADE,
  can_read_mentions     INTEGER NOT NULL DEFAULT 0 CHECK (can_read_mentions IN (0,1)),
  can_write             INTEGER NOT NULL DEFAULT 0 CHECK (can_write IN (0,1)),
  source                TEXT NOT NULL CHECK (source IN ('nip65','follow_tag','manual','observed','default')),
  source_event_id       TEXT REFERENCES events(id) ON DELETE SET NULL,
  priority              INTEGER NOT NULL DEFAULT 100,
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (pubkey, relay_id, source)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_author_relays_pubkey_write
  ON author_relays(pubkey, can_write, priority);

CREATE INDEX IF NOT EXISTS idx_author_relays_pubkey_read
  ON author_relays(pubkey, can_read_mentions, priority);

CREATE TABLE IF NOT EXISTS local_profile_notes (
  account_id            INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  target_pubkey         TEXT NOT NULL CHECK (length(target_pubkey) = 64),
  note                  TEXT NOT NULL DEFAULT '',
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (account_id, target_pubkey)
) WITHOUT ROWID;

-- ============================================================
-- 7. Lists/mutes/bookmarks/pins
-- ============================================================
CREATE TABLE IF NOT EXISTS user_lists (
  owner_pubkey          TEXT NOT NULL CHECK (length(owner_pubkey) = 64),
  kind                  INTEGER NOT NULL,
  d_tag                 TEXT NOT NULL DEFAULT '',
  title                 TEXT,
  source_event_id       TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  created_at            INTEGER NOT NULL,
  encrypted_content     TEXT,
  decrypted_at_ms       INTEGER,
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (owner_pubkey, kind, d_tag)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS user_list_items (
  owner_pubkey          TEXT NOT NULL,
  kind                  INTEGER NOT NULL,
  d_tag                 TEXT NOT NULL DEFAULT '',
  item_index            INTEGER NOT NULL,
  tag_name              TEXT NOT NULL,
  value                 TEXT NOT NULL,
  relay_url             TEXT,
  marker                TEXT,
  extra_json            TEXT NOT NULL DEFAULT '[]',
  is_private            INTEGER NOT NULL DEFAULT 0 CHECK (is_private IN (0,1)),
  source_event_id       TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  PRIMARY KEY (owner_pubkey, kind, d_tag, item_index)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_user_list_items_lookup
  ON user_list_items(owner_pubkey, kind, tag_name, value);

CREATE TABLE IF NOT EXISTS mute_rules (
  account_pubkey        TEXT NOT NULL CHECK (length(account_pubkey) = 64),
  rule_type             TEXT NOT NULL CHECK (rule_type IN ('pubkey','event','thread','hashtag','word','regex','relay','kind')),
  value                 TEXT NOT NULL,
  is_private            INTEGER NOT NULL DEFAULT 0 CHECK (is_private IN (0,1)),
  expires_at_ms         INTEGER,
  source                TEXT NOT NULL CHECK (source IN ('nip51','local','imported')),
  source_event_id       TEXT REFERENCES events(id) ON DELETE SET NULL,
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (account_pubkey, rule_type, value)
) WITHOUT ROWID;

-- ============================================================
-- 8. Social projections: notes, threads, reposts, reactions, stats
-- ============================================================
CREATE TABLE IF NOT EXISTS notes (
  event_id              TEXT PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,
  author_pubkey         TEXT NOT NULL CHECK (length(author_pubkey) = 64),
  created_at            INTEGER NOT NULL,
  root_event_id         TEXT,
  reply_to_event_id     TEXT,
  quote_event_id        TEXT,
  is_reply              INTEGER NOT NULL DEFAULT 0 CHECK (is_reply IN (0,1)),
  is_quote              INTEGER NOT NULL DEFAULT 0 CHECK (is_quote IN (0,1)),
  has_media             INTEGER NOT NULL DEFAULT 0 CHECK (has_media IN (0,1)),
  has_link              INTEGER NOT NULL DEFAULT 0 CHECK (has_link IN (0,1)),
  content_warning       TEXT,
  searchable_text       TEXT,
  parsed_entities_json  TEXT,
  updated_at_ms         INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_notes_author_created
  ON notes(author_pubkey, created_at DESC, event_id ASC);

CREATE INDEX IF NOT EXISTS idx_notes_root
  ON notes(root_event_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_notes_reply_to
  ON notes(reply_to_event_id, created_at ASC);

CREATE TABLE IF NOT EXISTS note_relations (
  event_id              TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  relation_type         TEXT NOT NULL CHECK (relation_type IN ('root','reply','quote','mention','hashtag','url','media')),
  target_value          TEXT NOT NULL,
  target_pubkey         TEXT,
  target_kind           INTEGER,
  relay_url             TEXT,
  position              INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (event_id, relation_type, position)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_note_relations_type_target
  ON note_relations(relation_type, target_value, event_id);

CREATE TABLE IF NOT EXISTS reposts (
  repost_event_id       TEXT PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,
  target_event_id       TEXT,
  target_addr           TEXT,
  reposter_pubkey       TEXT NOT NULL CHECK (length(reposter_pubkey) = 64),
  created_at            INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_reposts_target
  ON reposts(target_event_id, created_at DESC);

CREATE TABLE IF NOT EXISTS reactions (
  reaction_event_id     TEXT PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,
  target_event_id       TEXT,
  target_addr           TEXT,
  reactor_pubkey        TEXT NOT NULL CHECK (length(reactor_pubkey) = 64),
  reaction              TEXT NOT NULL,
  is_like               INTEGER NOT NULL DEFAULT 0 CHECK (is_like IN (0,1)),
  is_dislike            INTEGER NOT NULL DEFAULT 0 CHECK (is_dislike IN (0,1)),
  created_at            INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_reactions_target
  ON reactions(target_event_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reactions_target_like
  ON reactions(target_event_id, is_like);

CREATE TABLE IF NOT EXISTS event_stats (
  event_id              TEXT PRIMARY KEY,
  replies_local         INTEGER NOT NULL DEFAULT 0,
  reposts_local         INTEGER NOT NULL DEFAULT 0,
  reactions_local       INTEGER NOT NULL DEFAULT 0,
  likes_local           INTEGER NOT NULL DEFAULT 0,
  dislikes_local        INTEGER NOT NULL DEFAULT 0,
  replies_approx        INTEGER,
  reposts_approx        INTEGER,
  reactions_approx      INTEGER,
  hll_replies           BLOB,
  hll_reposts           BLOB,
  hll_reactions         BLOB,
  updated_at_ms         INTEGER NOT NULL
);

-- ============================================================
-- 9. Feed materialization and UX state
-- ============================================================
CREATE TABLE IF NOT EXISTS feeds (
  id                    INTEGER PRIMARY KEY,
  account_id            INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  type                  TEXT NOT NULL CHECK (type IN ('home','notifications','profile','list','hashtag','search','thread','global','relay')),
  title                 TEXT,
  params_json           TEXT NOT NULL DEFAULT '{}',
  include_replies       INTEGER NOT NULL DEFAULT 0,
  include_reposts       INTEGER NOT NULL DEFAULT 1,
  relay_set_hash        TEXT,
  created_at_ms         INTEGER NOT NULL,
  updated_at_ms         INTEGER NOT NULL,
  UNIQUE (account_id, type, params_json)
);

CREATE TABLE IF NOT EXISTS feed_items (
  feed_id               INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  item_key              TEXT NOT NULL,
  source_event_id       TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  subject_event_id      TEXT,
  reason                TEXT NOT NULL CHECK (reason IN ('author','reply','repost','quote','mention','reaction','zap','follow','manual')),
  actor_pubkey          TEXT,
  sort_at               INTEGER NOT NULL,
  tie_break_id          TEXT NOT NULL,
  hidden_reason         TEXT,
  collapsed             INTEGER NOT NULL DEFAULT 0 CHECK (collapsed IN (0,1)),
  pending_new           INTEGER NOT NULL DEFAULT 0 CHECK (pending_new IN (0,1)),
  inserted_at_ms        INTEGER NOT NULL,
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (feed_id, item_key)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_feed_items_order
  ON feed_items(feed_id, sort_at DESC, tie_break_id ASC);

CREATE INDEX IF NOT EXISTS idx_feed_items_subject
  ON feed_items(subject_event_id);

CREATE INDEX IF NOT EXISTS idx_feed_items_source
  ON feed_items(source_event_id);

CREATE TABLE IF NOT EXISTS feed_render_hints (
  feed_id               INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  item_key              TEXT NOT NULL,
  root_event_id         TEXT,
  parent_event_id       TEXT,
  repost_target_event_id TEXT,
  quote_target_event_id TEXT,
  effective_profile_event_id TEXT,
  flags                 INTEGER NOT NULL DEFAULT 0,
  link_preview_url      TEXT,
  media_count           INTEGER NOT NULL DEFAULT 0,
  resolve_state_json    TEXT NOT NULL DEFAULT '{}',
  layout_contract_json  TEXT NOT NULL DEFAULT '{}',
  hints_json            TEXT NOT NULL DEFAULT '{}',
  updated_at_ms         INTEGER NOT NULL,
  PRIMARY KEY (feed_id, item_key),
  FOREIGN KEY (feed_id, item_key) REFERENCES feed_items(feed_id, item_key) ON DELETE CASCADE
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS feed_read_state (
  account_id              INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  feed_id                 INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  marker_sort_at          INTEGER,
  marker_event_id         TEXT,
  scroll_anchor_item_key  TEXT,
  scroll_anchor_event_id  TEXT,
  scroll_anchor_sort_at   INTEGER,
  scroll_anchor_tie_break_id TEXT,
  scroll_anchor_offset_px INTEGER NOT NULL DEFAULT 0,
  viewport_height_px      INTEGER,
  viewport_width_px       INTEGER,
  content_inset_top_px    INTEGER,
  content_inset_bottom_px INTEGER,
  last_visible_top_id     TEXT,
  last_visible_bottom_id  TEXT,
  restore_fallback_reason TEXT,
  client_state_json       TEXT NOT NULL DEFAULT '{}',
  last_viewed_at_ms       INTEGER NOT NULL,
  updated_at_ms           INTEGER NOT NULL,
  PRIMARY KEY (account_id, feed_id)
) WITHOUT ROWID;


CREATE TABLE IF NOT EXISTS timeline_row_layout_cache (
  feed_id                 INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  item_key                TEXT NOT NULL,
  row_width_px            INTEGER NOT NULL,
  measured_height_px      INTEGER NOT NULL,
  layout_contract_hash    TEXT NOT NULL,
  first_measured_at_ms    INTEGER NOT NULL,
  last_measured_at_ms     INTEGER NOT NULL,
  invalidated_at_ms       INTEGER,
  PRIMARY KEY (feed_id, item_key, row_width_px, layout_contract_hash),
  FOREIGN KEY (feed_id, item_key) REFERENCES feed_items(feed_id, item_key) ON DELETE CASCADE
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_timeline_row_layout_cache_invalidated
  ON timeline_row_layout_cache(invalidated_at_ms);

CREATE TABLE IF NOT EXISTS feed_gaps (
  id                      INTEGER PRIMARY KEY,
  feed_id                 INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  newer_boundary_sort_at  INTEGER,
  newer_boundary_event_id TEXT,
  older_boundary_sort_at  INTEGER,
  older_boundary_event_id TEXT,
  relay_set_hash          TEXT NOT NULL,
  state                   TEXT NOT NULL CHECK (state IN ('open','filling','filled','exhausted','failed')),
  last_attempt_at_ms      INTEGER,
  filled_at_ms            INTEGER,
  error                   TEXT,
  created_at_ms           INTEGER NOT NULL,
  updated_at_ms           INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_feed_gaps_feed_state
  ON feed_gaps(feed_id, state);

-- ============================================================
-- 10. Sync cursors and missing event hydration
-- ============================================================
CREATE TABLE IF NOT EXISTS sync_cursors (
  account_id             INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  relay_id               INTEGER NOT NULL REFERENCES relays(id) ON DELETE CASCADE,
  scope                  TEXT NOT NULL,
  filter_hash            TEXT NOT NULL,
  newest_seen_created_at INTEGER,
  newest_seen_event_id   TEXT,
  oldest_seen_created_at INTEGER,
  oldest_seen_event_id   TEXT,
  last_eose_at_ms        INTEGER,
  last_request_at_ms     INTEGER,
  last_success_at_ms     INTEGER,
  last_error_at_ms       INTEGER,
  last_error             TEXT,
  PRIMARY KEY (account_id, relay_id, scope, filter_hash)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS missing_events (
  event_id               TEXT PRIMARY KEY CHECK (length(event_id) = 64),
  expected_pubkey        TEXT,
  expected_kind          INTEGER,
  relay_hints_json       TEXT,
  reason                 TEXT NOT NULL CHECK (reason IN ('reply_root','reply_parent','repost_target','quote_target','notification_target','profile','unknown')),
  first_requested_at_ms  INTEGER,
  last_requested_at_ms   INTEGER,
  attempts               INTEGER NOT NULL DEFAULT 0,
  resolved_event_id      TEXT,
  state                  TEXT NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending','fetching','resolved','failed','ignored'))
);

CREATE INDEX IF NOT EXISTS idx_missing_events_state
  ON missing_events(state, last_requested_at_ms);


-- ============================================================
-- 10b. Delayed resolve jobs
-- ============================================================
CREATE TABLE IF NOT EXISTS resolve_jobs (
  id                      INTEGER PRIMARY KEY,
  account_id              INTEGER REFERENCES accounts(id) ON DELETE CASCADE,
  feed_id                 INTEGER REFERENCES feeds(id) ON DELETE CASCADE,
  item_key                TEXT,
  source_event_id         TEXT REFERENCES events(id) ON DELETE CASCADE,
  job_type                TEXT NOT NULL CHECK (job_type IN (
    'ogp','media_metadata','media_bytes','profile','repost_target','quote_target',
    'reply_parent','reply_root','nip05','stats'
  )),
  target_key              TEXT NOT NULL,
  target_event_id         TEXT,
  target_pubkey           TEXT,
  relay_hints_json        TEXT NOT NULL DEFAULT '[]',
  priority                INTEGER NOT NULL DEFAULT 100,
  state                   TEXT NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending','resolving','resolved','failed','blocked','unavailable','cancelled')),
  attempts                INTEGER NOT NULL DEFAULT 0,
  max_attempts            INTEGER NOT NULL DEFAULT 5,
  timeout_ms              INTEGER NOT NULL DEFAULT 5000,
  next_attempt_at_ms      INTEGER,
  last_attempt_at_ms      INTEGER,
  resolved_at_ms          INTEGER,
  last_error              TEXT,
  result_json             TEXT NOT NULL DEFAULT '{}',
  created_at_ms           INTEGER NOT NULL,
  updated_at_ms           INTEGER NOT NULL,
  FOREIGN KEY (feed_id, item_key) REFERENCES feed_items(feed_id, item_key) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_resolve_jobs_state_priority
  ON resolve_jobs(state, priority, next_attempt_at_ms);

CREATE INDEX IF NOT EXISTS idx_resolve_jobs_target
  ON resolve_jobs(job_type, target_key);

CREATE UNIQUE INDEX IF NOT EXISTS idx_resolve_jobs_unique_active
  ON resolve_jobs(job_type, target_key, COALESCE(feed_id, -1), COALESCE(item_key, ''))
  WHERE state IN ('pending','resolving');

-- ============================================================
-- 11. Notifications
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  account_id            INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  notification_key      TEXT NOT NULL,
  event_id              TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  type                  TEXT NOT NULL CHECK (type IN ('mention','reply','quote','reaction','repost','zap','follow')),
  actor_pubkey          TEXT NOT NULL,
  target_event_id       TEXT,
  created_at            INTEGER NOT NULL,
  read_at_ms            INTEGER,
  hidden_reason         TEXT,
  inserted_at_ms        INTEGER NOT NULL,
  PRIMARY KEY (account_id, notification_key)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_notifications_order
  ON notifications(account_id, created_at DESC);

-- ============================================================
-- 12. Compose / publish / drafts
-- ============================================================
CREATE TABLE IF NOT EXISTS drafts (
  id                    INTEGER PRIMARY KEY,
  account_id            INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind                  INTEGER NOT NULL DEFAULT 1,
  content               TEXT NOT NULL DEFAULT '',
  tags_json             TEXT NOT NULL DEFAULT '[]',
  reply_to_event_id     TEXT,
  quote_event_id        TEXT,
  client_state_json     TEXT NOT NULL DEFAULT '{}',
  created_at_ms         INTEGER NOT NULL,
  updated_at_ms         INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS publish_queue (
  id                    INTEGER PRIMARY KEY,
  account_id            INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  event_id              TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  raw_json              TEXT NOT NULL,
  state                 TEXT NOT NULL CHECK (state IN ('queued','signing','publishing','partial','published','failed','cancelled')),
  target_relays_json    TEXT NOT NULL,
  created_at_ms         INTEGER NOT NULL,
  next_attempt_at_ms    INTEGER,
  attempts              INTEGER NOT NULL DEFAULT 0,
  last_error            TEXT
);

CREATE INDEX IF NOT EXISTS idx_publish_queue_state_next
  ON publish_queue(state, next_attempt_at_ms);

CREATE TABLE IF NOT EXISTS publish_receipts (
  event_id              TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  relay_id              INTEGER NOT NULL REFERENCES relays(id) ON DELETE CASCADE,
  accepted              INTEGER CHECK (accepted IN (0,1) OR accepted IS NULL),
  message               TEXT,
  attempted_at_ms       INTEGER NOT NULL,
  PRIMARY KEY (event_id, relay_id)
) WITHOUT ROWID;

-- ============================================================
-- 13. Media / link preview / external identity cache
-- ============================================================
CREATE TABLE IF NOT EXISTS media_assets (
  id                    INTEGER PRIMARY KEY,
  url                   TEXT,
  sha256                TEXT,
  cache_key             TEXT NOT NULL UNIQUE,
  local_path            TEXT,
  mime_type             TEXT,
  size_bytes            INTEGER,
  width                 INTEGER,
  height                INTEGER,
  aspect_ratio          REAL,
  blurhash              TEXT,
  alt_text              TEXT,
  placeholder_policy    TEXT NOT NULL DEFAULT 'fixed_unknown'
    CHECK (placeholder_policy IN ('fixed_unknown','aspect_known','compact','blocked','none')),
  source_event_id       TEXT REFERENCES events(id) ON DELETE SET NULL,
  download_state        TEXT NOT NULL DEFAULT 'pending'
    CHECK (download_state IN ('pending','resolving','ready','failed','blocked','expired')),
  upload_state          TEXT DEFAULT 'none' CHECK (upload_state IN ('none','queued','uploading','uploaded','failed')),
  last_accessed_at_ms   INTEGER NOT NULL,
  expires_at_ms         INTEGER,
  metadata_json         TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_media_assets_sha256
  ON media_assets(sha256);

CREATE INDEX IF NOT EXISTS idx_media_assets_access
  ON media_assets(last_accessed_at_ms);

CREATE TABLE IF NOT EXISTS link_previews (
  url                   TEXT PRIMARY KEY,
  canonical_url         TEXT,
  title                 TEXT,
  description           TEXT,
  image_url             TEXT,
  site_name             TEXT,
  fetched_at_ms         INTEGER,
  last_requested_at_ms  INTEGER,
  expires_at_ms         INTEGER,
  attempts              INTEGER NOT NULL DEFAULT 0,
  layout_mode           TEXT NOT NULL DEFAULT 'compact'
    CHECK (layout_mode IN ('url_only','compact','rich','blocked')),
  state                 TEXT NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending','resolving','ready','failed','blocked','expired')),
  error                 TEXT
);

CREATE TABLE IF NOT EXISTS nip05_cache (
  identifier            TEXT PRIMARY KEY,
  pubkey                TEXT,
  relays_json           TEXT,
  verified              INTEGER NOT NULL DEFAULT 0 CHECK (verified IN (0,1)),
  fetched_at_ms         INTEGER NOT NULL,
  expires_at_ms         INTEGER,
  error                 TEXT
);


-- ============================================================
-- 13b. Timeline UI diagnostics for tests and benchmarks
-- ============================================================
CREATE TABLE IF NOT EXISTS timeline_snapshot_diagnostics (
  id                      INTEGER PRIMARY KEY,
  account_id              INTEGER REFERENCES accounts(id) ON DELETE CASCADE,
  feed_id                 INTEGER REFERENCES feeds(id) ON DELETE CASCADE,
  scenario                TEXT NOT NULL,
  mutation_reason         TEXT NOT NULL,
  anchor_item_key         TEXT,
  before_frame_min_y      REAL,
  after_frame_min_y       REAL,
  anchor_delta_pt         REAL,
  before_visible_json     TEXT NOT NULL DEFAULT '[]',
  after_visible_json      TEXT NOT NULL DEFAULT '[]',
  read_marker_changed     INTEGER NOT NULL DEFAULT 0 CHECK (read_marker_changed IN (0,1)),
  created_at_ms           INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_timeline_snapshot_diagnostics_feed_time
  ON timeline_snapshot_diagnostics(feed_id, created_at_ms DESC);

-- ============================================================
-- 14. Retention / tombstones / maintenance
-- ============================================================
CREATE TABLE IF NOT EXISTS event_tombstones (
  id                    TEXT PRIMARY KEY CHECK (length(id) = 64),
  pubkey                TEXT,
  kind                  INTEGER,
  created_at            INTEGER,
  deleted_at            INTEGER,
  deleted_by_event_id   TEXT,
  pruned_at_ms          INTEGER,
  reason                TEXT
);

CREATE TABLE IF NOT EXISTS retention_pins (
  event_id              TEXT NOT NULL,
  reason                TEXT NOT NULL CHECK (reason IN ('own','bookmark','pin','notification','thread_opened','visible_recently','publish_queue','head','manual')),
  expires_at_ms         INTEGER,
  PRIMARY KEY (event_id, reason)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_retention_pins_expires
  ON retention_pins(expires_at_ms);

CREATE TABLE IF NOT EXISTS maintenance_jobs (
  id                    INTEGER PRIMARY KEY,
  job_type              TEXT NOT NULL CHECK (job_type IN ('checkpoint','incremental_vacuum','fts_rebuild','media_gc','db_optimize','prune')),
  state                 TEXT NOT NULL DEFAULT 'queued' CHECK (state IN ('queued','running','done','failed')),
  scheduled_at_ms       INTEGER NOT NULL,
  started_at_ms         INTEGER,
  finished_at_ms        INTEGER,
  detail_json           TEXT NOT NULL DEFAULT '{}',
  error                 TEXT
);

PRAGMA user_version = 2;

COMMIT;
