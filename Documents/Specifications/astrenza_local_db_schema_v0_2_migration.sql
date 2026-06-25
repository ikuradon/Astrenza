-- Astrenza Local DB migration v0 -> v0.2
-- Adds precise scroll-anchor metadata and delayed-resolve support.
-- Run once when PRAGMA user_version < 2.

PRAGMA foreign_keys = ON;

BEGIN;

-- ------------------------------------------------------------
-- feed_render_hints: delayed resolve / layout contract hints
-- ------------------------------------------------------------
ALTER TABLE feed_render_hints ADD COLUMN link_preview_url TEXT;
ALTER TABLE feed_render_hints ADD COLUMN media_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE feed_render_hints ADD COLUMN resolve_state_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE feed_render_hints ADD COLUMN layout_contract_json TEXT NOT NULL DEFAULT '{}';

-- ------------------------------------------------------------
-- feed_read_state: precise launch-time scroll restoration
-- ------------------------------------------------------------
ALTER TABLE feed_read_state ADD COLUMN scroll_anchor_item_key TEXT;
ALTER TABLE feed_read_state ADD COLUMN scroll_anchor_sort_at INTEGER;
ALTER TABLE feed_read_state ADD COLUMN scroll_anchor_tie_break_id TEXT;
ALTER TABLE feed_read_state ADD COLUMN viewport_height_px INTEGER;
ALTER TABLE feed_read_state ADD COLUMN viewport_width_px INTEGER;
ALTER TABLE feed_read_state ADD COLUMN content_inset_top_px INTEGER;
ALTER TABLE feed_read_state ADD COLUMN content_inset_bottom_px INTEGER;
ALTER TABLE feed_read_state ADD COLUMN restore_fallback_reason TEXT;
ALTER TABLE feed_read_state ADD COLUMN client_state_json TEXT NOT NULL DEFAULT '{}';

-- Best-effort backfill from old event-id anchor to item_key/sort key.
UPDATE feed_read_state
SET
  scroll_anchor_item_key = (
    SELECT fi.item_key
    FROM feed_items fi
    WHERE fi.feed_id = feed_read_state.feed_id
      AND fi.source_event_id = feed_read_state.scroll_anchor_event_id
      AND fi.hidden_reason IS NULL
    ORDER BY fi.sort_at DESC, fi.tie_break_id ASC
    LIMIT 1
  ),
  scroll_anchor_sort_at = (
    SELECT fi.sort_at
    FROM feed_items fi
    WHERE fi.feed_id = feed_read_state.feed_id
      AND fi.source_event_id = feed_read_state.scroll_anchor_event_id
      AND fi.hidden_reason IS NULL
    ORDER BY fi.sort_at DESC, fi.tie_break_id ASC
    LIMIT 1
  ),
  scroll_anchor_tie_break_id = (
    SELECT fi.tie_break_id
    FROM feed_items fi
    WHERE fi.feed_id = feed_read_state.feed_id
      AND fi.source_event_id = feed_read_state.scroll_anchor_event_id
      AND fi.hidden_reason IS NULL
    ORDER BY fi.sort_at DESC, fi.tie_break_id ASC
    LIMIT 1
  )
WHERE scroll_anchor_event_id IS NOT NULL
  AND scroll_anchor_item_key IS NULL;

-- ------------------------------------------------------------
-- timeline row layout cache: rebuildable local UX state
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- resolve_jobs: persistent delayed resolver queue
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- media_assets: download state and stable placeholder policy
-- ------------------------------------------------------------
ALTER TABLE media_assets ADD COLUMN aspect_ratio REAL;
ALTER TABLE media_assets ADD COLUMN placeholder_policy TEXT NOT NULL DEFAULT 'fixed_unknown'
  CHECK (placeholder_policy IN ('fixed_unknown','aspect_known','compact','blocked','none'));
ALTER TABLE media_assets ADD COLUMN download_state TEXT NOT NULL DEFAULT 'pending'
  CHECK (download_state IN ('pending','resolving','ready','failed','blocked','expired'));

-- Backfill download_state for rows that already have local files.
UPDATE media_assets
SET download_state = CASE
  WHEN local_path IS NOT NULL THEN 'ready'
  ELSE 'pending'
END;

UPDATE media_assets
SET aspect_ratio = CASE
  WHEN width IS NOT NULL AND height IS NOT NULL AND height > 0 THEN CAST(width AS REAL) / CAST(height AS REAL)
  ELSE NULL
END;

UPDATE media_assets
SET placeholder_policy = CASE
  WHEN aspect_ratio IS NOT NULL THEN 'aspect_known'
  ELSE placeholder_policy
END;

-- ------------------------------------------------------------
-- link_previews: rebuild to allow pending/resolving/expired states
-- ------------------------------------------------------------
ALTER TABLE link_previews RENAME TO link_previews_old;

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

INSERT INTO link_previews (
  url, canonical_url, title, description, image_url, site_name,
  fetched_at_ms, last_requested_at_ms, expires_at_ms, attempts,
  layout_mode, state, error
)
SELECT
  url, canonical_url, title, description, image_url, site_name,
  fetched_at_ms, fetched_at_ms, expires_at_ms, 0,
  CASE WHEN state = 'blocked' THEN 'blocked' ELSE 'compact' END,
  CASE WHEN state IN ('ready','failed','blocked') THEN state ELSE 'failed' END,
  error
FROM link_previews_old;

DROP TABLE link_previews_old;

-- ------------------------------------------------------------
-- timeline_snapshot_diagnostics: debug/test artifact support
-- ------------------------------------------------------------
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

PRAGMA user_version = 2;

COMMIT;
