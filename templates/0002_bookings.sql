-- Optional add-on: book a resource (a crew, a room, a cabin, a van) for a time range.
-- Copy to app/migrations/0002_bookings.sql (renumber if you already have 0002),
-- then: npx wrangler d1 migrations apply crm --local   and later --remote
--
-- Times are UTC text 'YYYY-MM-DD HH:MM:SS'. Ranges are half-open: [start_at, end_at).
-- A booking that ends at 12:00 and one that starts at 12:00 do NOT overlap.
--
-- Which statuses hold the slot is decided in ONE place: OCCUPYING_STATUSES in
-- templates/bookings.js. Every availability query, the overlap guard and the
-- calendar must use that constant. Writing the list by hand in a second query is
-- how "paid bookings are bookable twice" happens.

CREATE TABLE IF NOT EXISTS resources (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  name      TEXT NOT NULL UNIQUE,            -- 'Crew A', 'Van 2', 'Cabin 3'
  capacity  INTEGER NOT NULL DEFAULT 1,      -- parallel bookings allowed (1 = exclusive)
  active    INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1))
);

CREATE TABLE IF NOT EXISTS bookings (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  resource_id  INTEGER NOT NULL REFERENCES resources(id),
  lead_id      INTEGER REFERENCES leads(id),  -- the lead this came from, if any
  start_at     TEXT NOT NULL,
  end_at       TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'held'
               CHECK (status IN ('held','confirmed','paid','cancelled','done')),
  hold_until   TEXT,                          -- 'held' expires after this; cron releases it
  price        INTEGER,
  note         TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
  CHECK (end_at > start_at)
);

CREATE INDEX IF NOT EXISTS idx_bookings_resource_time ON bookings(resource_id, start_at, end_at);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);
