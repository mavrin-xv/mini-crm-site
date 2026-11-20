-- mini-crm-site: core schema. Apply with:
--   npx wrangler d1 migrations apply crm --remote     (production)
--   npx wrangler d1 migrations apply crm --local      (wrangler dev)
-- Never edit an applied migration. Add 0002_..., 0003_... instead.

-- One row per person. Phone is the natural key for service businesses:
-- people call back, change email, and type their name three ways.
CREATE TABLE IF NOT EXISTS contacts (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  phone       TEXT NOT NULL UNIQUE,          -- normalised: digits and a leading +
  email       TEXT,
  notes       TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- One row per request for work. A repeat customer has many leads.
CREATE TABLE IF NOT EXISTS leads (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  contact_id       INTEGER NOT NULL REFERENCES contacts(id),
  service          TEXT NOT NULL,             -- key from SERVICES in src/config.js
  message          TEXT,
  preferred_date   TEXT,                      -- YYYY-MM-DD or NULL
  area             TEXT,                      -- district / zip, free text
  status           TEXT NOT NULL DEFAULT 'new'
                   CHECK (status IN ('new','contacted','quoted','booked','done','lost','spam')),
  value            INTEGER,                   -- quoted or booked amount, whole currency units
  lost_reason      TEXT,
  next_action_at   TEXT,                      -- when the operator promised to follow up
  source           TEXT NOT NULL DEFAULT 'site', -- site / phone / referral / walk-in
  utm_source       TEXT,
  utm_medium       TEXT,
  utm_campaign     TEXT,
  first_contact_at TEXT,                      -- set once, on the first move out of 'new'
  last_touch_at    TEXT,                      -- last status change or note by the operator
  sla_alerted      INTEGER NOT NULL DEFAULT 0, -- 1 once the late-lead alert went out
  created_at       TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_leads_status  ON leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_created ON leads(created_at);
CREATE INDEX IF NOT EXISTS idx_leads_contact ON leads(contact_id);

-- Append-only activity log: status changes, notes, notification results.
-- This is what makes "how fast do we call back" answerable.
CREATE TABLE IF NOT EXISTS lead_events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  lead_id     INTEGER NOT NULL REFERENCES leads(id),
  kind        TEXT NOT NULL,                  -- created / status / note / notify_ok / notify_fail
  from_status TEXT,
  to_status   TEXT,
  note        TEXT,
  at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_events_lead ON lead_events(lead_id);

-- Cheap per-IP rate limit for the public form (no KV needed).
CREATE TABLE IF NOT EXISTS form_hits (
  ip_hash TEXT NOT NULL,
  at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_hits ON form_hits(ip_hash, at);
