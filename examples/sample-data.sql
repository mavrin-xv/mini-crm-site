-- Invented sample data for mini-crm-site (Northwind Cleaning). Not real people.
-- Load: python skills/crm-operate/scripts/report.py --dump examples/sample-data.sql
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

INSERT INTO contacts (id,name,phone,created_at) VALUES (1,'Riley Ford','+15552007919','2026-09-07 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (1,1,'regular','North side','lost',NULL,'went with someone else',NULL,'site','google','cpc','spring-deep','2026-09-07 13:52:00','2026-09-07 13:52:00','2026-09-07 13:49:00','2026-09-07 13:52:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (1,'created','new','2026-09-07 13:49:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (1,'status','new','contacted','2026-09-07 13:52:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (2,'Taylor Park','+15552015838','2026-09-08 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (2,2,'regular','Midtown','lost',NULL,'outside service area',NULL,'site',NULL,NULL,NULL,'2026-09-08 22:30:00','2026-09-08 22:30:00','2026-09-08 22:24:00','2026-09-08 22:30:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (2,'created','new','2026-09-08 22:24:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (2,'status','new','contacted','2026-09-08 22:30:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (3,'Sam Novak','+15552023757','2026-09-08 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (3,3,'deep','North side','quoted',260,NULL,'2026-09-13','site','flyer','offline','north-side','2026-09-08 13:56:00','2026-09-09 13:56:00','2026-09-08 13:47:00','2026-09-09 13:56:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (3,'created','new','2026-09-08 13:47:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (3,'status','new','contacted','2026-09-08 13:56:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (4,'Morgan Lane','+15552031676','2026-09-09 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (4,4,'regular','Lakeview','done',160,NULL,NULL,'site','flyer','offline','north-side','2026-09-10 00:39:00','2026-09-12 00:39:00','2026-09-09 14:39:00','2026-09-12 00:39:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (4,'created','new','2026-09-09 14:39:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (4,'status','new','contacted','2026-09-10 00:39:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (5,'Rowan Lane','+15552039595','2026-09-09 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (5,5,'deep','Lakeview','done',260,NULL,NULL,'site','google','cpc','brand','2026-09-09 18:18:00','2026-09-13 18:18:00','2026-09-09 18:06:00','2026-09-13 18:18:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (5,'created','new','2026-09-09 18:06:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (5,'status','new','contacted','2026-09-09 18:18:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (6,'Avery Wells','+15552047514','2026-09-10 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (6,6,'office','North side','done',460,NULL,NULL,'site','google','cpc','spring-deep','2026-09-10 14:36:00','2026-09-13 14:36:00','2026-09-10 14:14:00','2026-09-13 14:36:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (6,'created','new','2026-09-10 14:14:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (6,'status','new','contacted','2026-09-10 14:36:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (7,5,'move_out','Old town','quoted',380,NULL,'2026-09-12','site','facebook','paid_social','move-out','2026-09-12 08:46:00','2026-09-12 08:46:00','2026-09-11 22:46:00','2026-09-12 08:46:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (7,'created','new','2026-09-11 22:46:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (7,'status','new','contacted','2026-09-12 08:46:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (7,'Alex Hill','+15552055433','2026-09-11 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (8,7,'office','Lakeview','lost',NULL,'no answer after 3 calls',NULL,'referral',NULL,NULL,NULL,'2026-09-11 18:52:00','2026-09-11 18:52:00','2026-09-11 18:17:00','2026-09-11 18:52:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (8,'created','new','2026-09-11 18:17:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (8,'status','new','contacted','2026-09-11 18:52:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (8,'Blair Park','+15552063352','2026-09-11 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (9,8,'deep','Lakeview','lost',NULL,'date not available',NULL,'site','google','cpc','spring-deep','2026-09-11 21:34:00','2026-09-14 21:34:00','2026-09-11 21:25:00','2026-09-14 21:34:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (9,'created','new','2026-09-11 21:25:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (9,'status','new','contacted','2026-09-11 21:34:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (9,'Hayden Stone','+15552071271','2026-09-13 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (10,9,'move_out','Riverside','lost',NULL,'date not available',NULL,'site',NULL,NULL,NULL,'2026-09-13 15:42:00','2026-09-14 15:42:00','2026-09-13 15:20:00','2026-09-14 15:42:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (10,'created','new','2026-09-13 15:20:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (10,'status','new','contacted','2026-09-13 15:42:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (10,'Taylor Hill','+15552079190','2026-09-15 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (11,10,'deep','Midtown','done',260,NULL,NULL,'site','flyer','offline','north-side','2026-09-15 21:19:00','2026-09-19 21:19:00','2026-09-15 21:16:00','2026-09-19 21:19:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (11,'created','new','2026-09-15 21:16:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (11,'status','new','contacted','2026-09-15 21:19:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (11,'Emerson Wells','+15552087109','2026-09-16 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (12,11,'office','Riverside','done',460,NULL,NULL,'site',NULL,NULL,NULL,'2026-09-16 14:30:00','2026-09-16 14:30:00','2026-09-16 13:55:00','2026-09-16 14:30:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (12,'created','new','2026-09-16 13:55:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (12,'status','new','contacted','2026-09-16 14:30:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (12,'Jordan Lane','+15552095028','2026-09-18 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (13,12,'regular','Riverside','lost',NULL,'price',NULL,'site','google','cpc','spring-deep','2026-09-18 16:13:00','2026-09-18 16:13:00','2026-09-18 13:53:00','2026-09-18 16:13:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (13,'created','new','2026-09-18 13:53:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (13,'status','new','contacted','2026-09-18 16:13:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (13,'Jamie Lane','+15552102947','2026-09-19 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (14,13,'regular','Lakeview','spam',NULL,NULL,NULL,'site',NULL,NULL,NULL,'2026-09-19 20:12:00','2026-09-22 20:12:00','2026-09-19 19:12:00','2026-09-22 20:12:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (14,'created','new','2026-09-19 19:12:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (14,'status','new','contacted','2026-09-19 20:12:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (14,'Alex Reyes','+15552110866','2026-09-19 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (15,14,'move_out','North side','lost',NULL,'went with someone else',NULL,'referral',NULL,NULL,NULL,'2026-09-19 15:44:00','2026-09-23 15:44:00','2026-09-19 14:44:00','2026-09-23 15:44:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (15,'created','new','2026-09-19 14:44:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (15,'status','new','contacted','2026-09-19 15:44:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (15,'Emerson Lane','+15552118785','2026-09-20 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (16,15,'regular',NULL,'spam',NULL,NULL,NULL,'referral',NULL,NULL,NULL,'2026-09-20 15:44:00','2026-09-20 15:44:00','2026-09-20 15:30:00','2026-09-20 15:44:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (16,'created','new','2026-09-20 15:30:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (16,'status','new','contacted','2026-09-20 15:44:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (16,'Casey Lane','+15552126704','2026-09-21 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (17,16,'move_out','Lakeview','lost',NULL,'went with someone else',NULL,'site','flyer','offline','north-side','2026-09-22 02:48:00','2026-09-23 02:48:00','2026-09-21 16:48:00','2026-09-23 02:48:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (17,'created','new','2026-09-21 16:48:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (17,'status','new','contacted','2026-09-22 02:48:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (17,'Morgan Shaw','+15552134623','2026-09-22 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (18,17,'regular','Old town','lost',NULL,'no answer after 3 calls',NULL,'site','facebook','paid_social','move-out',NULL,NULL,'2026-09-22 21:24:00','2026-09-22 21:24:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (18,'created','new','2026-09-22 21:24:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (18,'Blair Lane','+15552142542','2026-09-22 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (19,18,'move_out','North side','lost',NULL,'no answer after 3 calls',NULL,'referral',NULL,NULL,NULL,NULL,NULL,'2026-09-22 20:37:00','2026-09-22 20:37:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (19,'created','new','2026-09-22 20:37:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (19,'Morgan Lane','+15552150461','2026-09-22 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (20,19,'regular','Lakeview','lost',NULL,'price',NULL,'site',NULL,NULL,NULL,'2026-09-22 16:51:00','2026-09-22 16:51:00','2026-09-22 16:29:00','2026-09-22 16:51:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (20,'created','new','2026-09-22 16:29:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (20,'status','new','contacted','2026-09-22 16:51:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (20,'Skyler Reyes','+15552158380','2026-09-23 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (21,20,'move_out','Riverside','quoted',320,NULL,'2026-09-29','referral',NULL,NULL,NULL,'2026-09-23 20:59:00','2026-09-24 20:59:00','2026-09-23 20:24:00','2026-09-24 20:59:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (21,'created','new','2026-09-23 20:24:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (21,'status','new','contacted','2026-09-23 20:59:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (21,'Dana Reyes','+15552166299','2026-09-23 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (22,21,'deep','Riverside','spam',NULL,NULL,NULL,'referral',NULL,NULL,NULL,'2026-09-24 06:56:00','2026-09-26 06:56:00','2026-09-23 20:56:00','2026-09-26 06:56:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (22,'created','new','2026-09-23 20:56:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (22,'status','new','contacted','2026-09-24 06:56:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (22,'Riley Hill','+15552174218','2026-09-23 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (23,22,'regular','North side','booked',120,NULL,NULL,'referral',NULL,NULL,NULL,'2026-09-23 13:23:00','2026-09-24 13:23:00','2026-09-23 13:14:00','2026-09-24 13:23:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (23,'created','new','2026-09-23 13:14:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (23,'status','new','contacted','2026-09-23 13:23:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (23,'Emerson Novak','+15552182137','2026-09-24 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (24,23,'move_out',NULL,'done',340,NULL,NULL,'site','facebook','paid_social','move-out','2026-09-24 23:09:00','2026-09-27 23:09:00','2026-09-24 23:00:00','2026-09-27 23:09:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (24,'created','new','2026-09-24 23:00:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (24,'status','new','contacted','2026-09-24 23:09:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (24,'Emerson Ford','+15552190056','2026-09-25 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (25,24,'deep','North side','lost',NULL,'went with someone else',NULL,'site','google','cpc','brand','2026-09-25 21:36:00','2026-09-29 21:36:00','2026-09-25 21:33:00','2026-09-29 21:36:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (25,'created','new','2026-09-25 21:33:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (25,'status','new','contacted','2026-09-25 21:36:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (25,'Riley Reyes','+15552197975','2026-09-25 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (26,25,'regular','Lakeview','lost',NULL,'outside service area',NULL,'site',NULL,NULL,NULL,'2026-09-25 15:46:00','2026-09-29 15:46:00','2026-09-25 15:24:00','2026-09-29 15:46:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (26,'created','new','2026-09-25 15:24:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (26,'status','new','contacted','2026-09-25 15:46:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (27,7,'regular','Old town','done',100,NULL,NULL,'site','google','cpc','spring-deep','2026-09-27 20:03:00','2026-09-30 20:03:00','2026-09-27 17:43:00','2026-09-30 20:03:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (27,'created','new','2026-09-27 17:43:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (27,'status','new','contacted','2026-09-27 20:03:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (26,'Emerson Wells','+15552205894','2026-09-27 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (28,26,'move_out',NULL,'lost',NULL,'outside service area',NULL,'site','google','cpc','brand','2026-09-28 00:04:00','2026-09-29 00:04:00','2026-09-27 21:44:00','2026-09-29 00:04:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (28,'created','new','2026-09-27 21:44:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (28,'status','new','contacted','2026-09-28 00:04:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (27,'Jamie Shaw','+15552213813','2026-09-28 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (29,27,'deep','Lakeview','booked',240,NULL,NULL,'site',NULL,NULL,NULL,'2026-09-28 17:02:00','2026-09-29 17:02:00','2026-09-28 16:27:00','2026-09-29 17:02:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (29,'created','new','2026-09-28 16:27:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (29,'status','new','contacted','2026-09-28 17:02:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (30,22,'deep','Riverside','lost',NULL,'no answer after 3 calls',NULL,'site','google','cpc','spring-deep',NULL,NULL,'2026-09-28 18:10:00','2026-09-28 18:10:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (30,'created','new','2026-09-28 18:10:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (28,'Rowan Novak','+15552221732','2026-09-29 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (31,28,'office','Lakeview','done',460,NULL,NULL,'site',NULL,NULL,NULL,'2026-09-29 14:48:00','2026-10-03 14:48:00','2026-09-29 14:36:00','2026-10-03 14:48:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (31,'created','new','2026-09-29 14:36:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (31,'status','new','contacted','2026-09-29 14:48:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (29,'Drew Lane','+15552229651','2026-09-30 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (32,29,'move_out','Midtown','quoted',320,NULL,'2026-10-04','referral',NULL,NULL,NULL,'2026-09-30 16:54:00','2026-10-02 16:54:00','2026-09-30 14:34:00','2026-10-02 16:54:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (32,'created','new','2026-09-30 14:34:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (32,'status','new','contacted','2026-09-30 16:54:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (30,'Alex Park','+15552237570','2026-10-01 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (33,30,'regular','Riverside','lost',NULL,'went with someone else',NULL,'site','google','cpc','spring-deep','2026-10-01 16:57:00','2026-10-03 16:57:00','2026-10-01 16:54:00','2026-10-03 16:57:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (33,'created','new','2026-10-01 16:54:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (33,'status','new','contacted','2026-10-01 16:57:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (31,'Jamie Ford','+15552245489','2026-10-01 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (34,31,'office','North side','done',420,NULL,NULL,'site','flyer','offline','north-side','2026-10-01 15:38:00','2026-10-04 15:38:00','2026-10-01 15:32:00','2026-10-04 15:38:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (34,'created','new','2026-10-01 15:32:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (34,'status','new','contacted','2026-10-01 15:38:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (32,'Alex Stone','+15552253408','2026-10-02 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (35,32,'deep','Old town','quoted',260,NULL,'2026-10-07','site','flyer','offline','north-side','2026-10-02 14:31:00','2026-10-05 14:31:00','2026-10-02 14:25:00','2026-10-05 14:31:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (35,'created','new','2026-10-02 14:25:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (35,'status','new','contacted','2026-10-02 14:31:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (36,16,'move_out','Riverside','lost',NULL,'no answer after 3 calls',NULL,'site','google','cpc','brand','2026-10-03 15:04:00','2026-10-07 15:04:00','2026-10-03 14:52:00','2026-10-07 15:04:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (36,'created','new','2026-10-03 14:52:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (36,'status','new','contacted','2026-10-03 15:04:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (33,'Emerson Price','+15552261327','2026-10-03 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (37,33,'move_out','Midtown','done',320,NULL,NULL,'site','facebook','paid_social','move-out','2026-10-03 16:16:00','2026-10-07 16:16:00','2026-10-03 16:02:00','2026-10-07 16:16:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (37,'created','new','2026-10-03 16:02:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (37,'status','new','contacted','2026-10-03 16:16:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (34,'Taylor Gray','+15552269246','2026-10-04 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (38,34,'office','Old town','lost',NULL,'date not available',NULL,'referral',NULL,NULL,NULL,'2026-10-04 17:08:00','2026-10-08 17:08:00','2026-10-04 14:48:00','2026-10-08 17:08:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (38,'created','new','2026-10-04 14:48:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (38,'status','new','contacted','2026-10-04 17:08:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (35,'Taylor Lane','+15552277165','2026-10-05 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (39,35,'deep','North side','spam',NULL,NULL,NULL,'referral',NULL,NULL,NULL,'2026-10-05 16:45:00','2026-10-06 16:45:00','2026-10-05 16:23:00','2026-10-06 16:45:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (39,'created','new','2026-10-05 16:23:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (39,'status','new','contacted','2026-10-05 16:45:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (40,17,'regular','Riverside','lost',NULL,'no answer after 3 calls',NULL,'site','google','cpc','brand','2026-10-05 20:56:00','2026-10-09 20:56:00','2026-10-05 20:21:00','2026-10-09 20:56:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (40,'created','new','2026-10-05 20:21:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (40,'status','new','contacted','2026-10-05 20:56:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (36,'Sam Gray','+15552285084','2026-10-05 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (41,36,'move_out','Old town','booked',340,NULL,NULL,'site','google','cpc','brand','2026-10-05 16:23:00','2026-10-09 16:23:00','2026-10-05 16:09:00','2026-10-09 16:23:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (41,'created','new','2026-10-05 16:09:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (41,'status','new','contacted','2026-10-05 16:23:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (42,20,'deep',NULL,'done',260,NULL,NULL,'site','facebook','paid_social','move-out','2026-10-06 17:18:00','2026-10-10 17:18:00','2026-10-06 16:43:00','2026-10-10 17:18:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (42,'created','new','2026-10-06 16:43:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (42,'status','new','contacted','2026-10-06 17:18:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (37,'Dana Park','+15552293003','2026-10-07 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (43,37,'deep',NULL,'booked',260,NULL,NULL,'site','google','cpc','spring-deep','2026-10-07 17:33:00','2026-10-09 17:33:00','2026-10-07 17:30:00','2026-10-09 17:33:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (43,'created','new','2026-10-07 17:30:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (43,'status','new','contacted','2026-10-07 17:33:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (44,34,'office',NULL,'done',420,NULL,NULL,'referral',NULL,NULL,NULL,'2026-10-08 16:38:00','2026-10-08 16:38:00','2026-10-08 15:38:00','2026-10-08 16:38:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (44,'created','new','2026-10-08 15:38:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (44,'status','new','contacted','2026-10-08 16:38:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (38,'Emerson Reyes','+15552300922','2026-10-09 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (45,38,'regular','North side','lost',NULL,'went with someone else',NULL,'site','flyer','offline','north-side','2026-10-10 07:56:00','2026-10-10 07:56:00','2026-10-09 21:56:00','2026-10-10 07:56:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (45,'created','new','2026-10-09 21:56:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (45,'status','new','contacted','2026-10-10 07:56:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (46,24,'office','Lakeview','contacted',NULL,NULL,'2026-10-15','site',NULL,NULL,NULL,'2026-10-09 14:50:00','2026-10-10 14:50:00','2026-10-09 14:47:00','2026-10-10 14:50:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (46,'created','new','2026-10-09 14:47:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (46,'status','new','contacted','2026-10-09 14:50:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (47,5,'regular','North side','lost',NULL,'date not available',NULL,'site','flyer','offline','north-side','2026-10-10 21:41:00','2026-10-12 21:41:00','2026-10-10 21:35:00','2026-10-12 21:41:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (47,'created','new','2026-10-10 21:35:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (47,'status','new','contacted','2026-10-10 21:41:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (39,'Morgan Novak','+15552308841','2026-10-11 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (48,39,'office','North side','lost',NULL,'outside service area',NULL,'site',NULL,NULL,NULL,'2026-10-11 21:05:00','2026-10-12 21:05:00','2026-10-11 20:51:00','2026-10-12 21:05:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (48,'created','new','2026-10-11 20:51:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (48,'status','new','contacted','2026-10-11 21:05:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (49,17,'deep',NULL,'quoted',240,NULL,'2026-10-18','site','flyer','offline','north-side','2026-10-12 18:14:00','2026-10-13 18:14:00','2026-10-12 18:11:00','2026-10-13 18:14:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (49,'created','new','2026-10-12 18:11:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (49,'status','new','contacted','2026-10-12 18:14:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (40,'Emerson Stone','+15552316760','2026-10-12 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (50,40,'office','Old town','done',460,NULL,NULL,'site',NULL,NULL,NULL,'2026-10-12 23:15:00','2026-10-12 23:15:00','2026-10-12 20:55:00','2026-10-12 23:15:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (50,'created','new','2026-10-12 20:55:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (50,'status','new','contacted','2026-10-12 23:15:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (51,33,'office',NULL,'done',400,NULL,NULL,'site','facebook','paid_social','move-out','2026-10-13 20:52:00','2026-10-14 20:52:00','2026-10-13 20:40:00','2026-10-14 20:52:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (51,'created','new','2026-10-13 20:40:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (51,'status','new','contacted','2026-10-13 20:52:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (41,'Drew Reyes','+15552324679','2026-10-13 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (52,41,'regular','Riverside','quoted',160,NULL,'2026-10-17','site','facebook','paid_social','move-out','2026-10-13 21:52:00','2026-10-13 21:52:00','2026-10-13 21:40:00','2026-10-13 21:52:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (52,'created','new','2026-10-13 21:40:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (52,'status','new','contacted','2026-10-13 21:52:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (42,'Parker Stone','+15552332598','2026-10-15 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (53,42,'move_out','Old town','lost',NULL,'price',NULL,'site',NULL,NULL,NULL,'2026-10-15 15:30:00','2026-10-17 15:30:00','2026-10-15 15:24:00','2026-10-17 15:30:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (53,'created','new','2026-10-15 15:24:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (53,'status','new','contacted','2026-10-15 15:30:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (43,'Jordan Novak','+15552340517','2026-10-15 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (54,43,'move_out','Lakeview','booked',320,NULL,NULL,'referral',NULL,NULL,NULL,'2026-10-15 13:18:00','2026-10-17 13:18:00','2026-10-15 13:12:00','2026-10-17 13:18:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (54,'created','new','2026-10-15 13:12:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (54,'status','new','contacted','2026-10-15 13:18:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (44,'Jamie Park','+15552348436','2026-10-16 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (55,44,'move_out','Midtown','done',340,NULL,NULL,'referral',NULL,NULL,NULL,'2026-10-16 14:01:00','2026-10-19 14:01:00','2026-10-16 13:52:00','2026-10-19 14:01:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (55,'created','new','2026-10-16 13:52:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (55,'status','new','contacted','2026-10-16 14:01:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (45,'Drew Ford','+15552356355','2026-10-17 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (56,45,'office','Riverside','lost',NULL,'no answer after 3 calls',NULL,'referral',NULL,NULL,NULL,NULL,NULL,'2026-10-17 13:29:00','2026-10-17 13:29:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (56,'created','new','2026-10-17 13:29:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (57,27,'deep','Lakeview','quoted',260,NULL,'2026-10-20','site','flyer','offline','north-side','2026-10-18 20:55:00','2026-10-21 20:55:00','2026-10-18 20:41:00','2026-10-21 20:55:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (57,'created','new','2026-10-18 20:41:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (57,'status','new','contacted','2026-10-18 20:55:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (46,'Avery Stone','+15552364274','2026-10-18 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (58,46,'deep',NULL,'contacted',NULL,NULL,'2026-10-19','site',NULL,NULL,NULL,'2026-10-18 19:46:00','2026-10-19 19:46:00','2026-10-18 17:26:00','2026-10-19 19:46:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (58,'created','new','2026-10-18 17:26:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (58,'status','new','contacted','2026-10-18 19:46:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (47,'Morgan Shaw','+15552372193','2026-10-18 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (59,47,'deep','Lakeview','spam',NULL,NULL,NULL,'site','flyer','offline','north-side','2026-10-18 21:51:00','2026-10-21 21:51:00','2026-10-18 21:29:00','2026-10-21 21:51:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (59,'created','new','2026-10-18 21:29:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (59,'status','new','contacted','2026-10-18 21:51:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (48,'Taylor Park','+15552380112','2026-10-19 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (60,48,'regular',NULL,'done',120,NULL,NULL,'site','facebook','paid_social','move-out','2026-10-19 16:20:00','2026-10-19 16:20:00','2026-10-19 15:58:00','2026-10-19 16:20:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (60,'created','new','2026-10-19 15:58:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (60,'status','new','contacted','2026-10-19 16:20:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (49,'Emerson Novak','+15552388031','2026-10-20 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (61,49,'move_out',NULL,'done',340,NULL,NULL,'site','facebook','paid_social','move-out','2026-10-20 20:25:00','2026-10-21 20:25:00','2026-10-20 19:25:00','2026-10-21 20:25:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (61,'created','new','2026-10-20 19:25:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (61,'status','new','contacted','2026-10-20 20:25:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (50,'Morgan Park','+15552395950','2026-10-20 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (62,50,'office','Riverside','booked',420,NULL,NULL,'site','google','cpc','brand','2026-10-20 18:37:00','2026-10-20 18:37:00','2026-10-20 17:37:00','2026-10-20 18:37:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (62,'created','new','2026-10-20 17:37:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (62,'status','new','contacted','2026-10-20 18:37:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (51,'Skyler Wells','+15552403869','2026-10-22 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (63,51,'regular','North side','lost',NULL,'date not available',NULL,'site','google','cpc','spring-deep','2026-10-22 23:41:00','2026-10-23 23:41:00','2026-10-22 21:21:00','2026-10-23 23:41:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (63,'created','new','2026-10-22 21:21:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (63,'status','new','contacted','2026-10-22 23:41:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (52,'Riley Shaw','+15552411788','2026-10-22 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (64,52,'office','Midtown','done',420,NULL,NULL,'referral',NULL,NULL,NULL,'2026-10-22 14:54:00','2026-10-23 14:54:00','2026-10-22 14:51:00','2026-10-23 14:54:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (64,'created','new','2026-10-22 14:51:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (64,'status','new','contacted','2026-10-22 14:54:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (53,'Riley Price','+15552419707','2026-10-24 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (65,53,'office','Midtown','done',420,NULL,NULL,'site','flyer','offline','north-side','2026-10-24 17:23:00','2026-10-28 17:23:00','2026-10-24 17:17:00','2026-10-28 17:23:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (65,'created','new','2026-10-24 17:17:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (65,'status','new','contacted','2026-10-24 17:23:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (54,'Jamie Novak','+15552427626','2026-10-24 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (66,54,'move_out',NULL,'lost',NULL,'no answer after 3 calls',NULL,'site','google','cpc','spring-deep',NULL,NULL,'2026-10-24 13:01:00','2026-10-24 13:01:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (66,'created','new','2026-10-24 13:01:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (55,'Taylor Gray','+15552435545','2026-10-24 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (67,55,'deep','North side','lost',NULL,'no answer after 3 calls',NULL,'site','google','cpc','brand','2026-10-24 22:33:00','2026-10-24 22:33:00','2026-10-24 21:58:00','2026-10-24 22:33:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (67,'created','new','2026-10-24 21:58:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (67,'status','new','contacted','2026-10-24 22:33:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (56,'Reese Park','+15552443464','2026-10-25 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (68,56,'office',NULL,'lost',NULL,'no answer after 3 calls',NULL,'site','google','cpc','brand',NULL,NULL,'2026-10-25 17:23:00','2026-10-25 17:23:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (68,'created','new','2026-10-25 17:23:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (57,'Drew Price','+15552451383','2026-10-26 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (69,57,'regular','Riverside','lost',NULL,'went with someone else',NULL,'site','google','cpc','brand','2026-10-26 22:05:00','2026-10-28 22:05:00','2026-10-26 19:45:00','2026-10-28 22:05:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (69,'created','new','2026-10-26 19:45:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (69,'status','new','contacted','2026-10-26 22:05:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (58,'Jamie Stone','+15552459302','2026-10-27 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (70,58,'office','Lakeview','quoted',400,NULL,'2026-11-01','site','flyer','offline','north-side','2026-10-27 15:03:00','2026-10-28 15:03:00','2026-10-27 14:51:00','2026-10-28 15:03:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (70,'created','new','2026-10-27 14:51:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (70,'status','new','contacted','2026-10-27 15:03:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (71,39,'regular','North side','booked',120,NULL,NULL,'site',NULL,NULL,NULL,'2026-10-29 15:34:00','2026-10-29 15:34:00','2026-10-29 15:25:00','2026-10-29 15:34:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (71,'created','new','2026-10-29 15:25:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (71,'status','new','contacted','2026-10-29 15:34:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (59,'Casey Price','+15552467221','2026-10-30 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (72,59,'office','Riverside','lost',NULL,'no answer after 3 calls',NULL,'referral',NULL,NULL,NULL,'2026-10-30 22:32:00','2026-11-02 22:32:00','2026-10-30 21:57:00','2026-11-02 22:32:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (72,'created','new','2026-10-30 21:57:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (72,'status','new','contacted','2026-10-30 22:32:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (73,27,'deep','North side','lost',NULL,'date not available',NULL,'site','flyer','offline','north-side','2026-11-03 15:20:00','2026-11-03 15:20:00','2026-11-03 15:06:00','2026-11-03 15:20:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (73,'created','new','2026-11-03 15:06:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (73,'status','new','contacted','2026-11-03 15:20:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (60,'Drew Shaw','+15552475140','2026-11-04 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (74,60,'move_out',NULL,'done',380,NULL,NULL,'site','google','cpc','brand','2026-11-04 21:37:00','2026-11-05 21:37:00','2026-11-04 20:37:00','2026-11-05 21:37:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (74,'created','new','2026-11-04 20:37:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (74,'status','new','contacted','2026-11-04 21:37:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (61,'Sam Ford','+15552483059','2026-11-04 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (75,61,'regular','Old town','done',100,NULL,NULL,'site',NULL,NULL,NULL,'2026-11-04 13:38:00','2026-11-08 13:38:00','2026-11-04 13:35:00','2026-11-08 13:38:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (75,'created','new','2026-11-04 13:35:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (75,'status','new','contacted','2026-11-04 13:38:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (62,'Quinn Wells','+15552490978','2026-11-04 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (76,62,'move_out',NULL,'lost',NULL,'no answer after 3 calls',NULL,'site','facebook','paid_social','move-out',NULL,NULL,'2026-11-04 13:44:00','2026-11-04 13:44:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (76,'created','new','2026-11-04 13:44:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (77,46,'move_out','Lakeview','lost',NULL,'no answer after 3 calls',NULL,'site',NULL,NULL,NULL,NULL,NULL,'2026-11-07 20:56:00','2026-11-07 20:56:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (77,'created','new','2026-11-07 20:56:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (78,60,'deep','Midtown','lost',NULL,'date not available',NULL,'referral',NULL,NULL,NULL,'2026-11-08 18:32:00','2026-11-10 18:32:00','2026-11-08 18:10:00','2026-11-10 18:32:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (78,'created','new','2026-11-08 18:10:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (78,'status','new','contacted','2026-11-08 18:32:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (63,'Casey Novak','+15552498897','2026-11-10 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (79,63,'regular','Old town','booked',100,NULL,NULL,'site','google','cpc','spring-deep','2026-11-10 22:17:00','2026-11-10 22:17:00','2026-11-10 19:57:00','2026-11-10 22:17:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (79,'created','new','2026-11-10 19:57:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (79,'status','new','contacted','2026-11-10 22:17:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (64,'Morgan Park','+15552506816','2026-11-10 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (80,64,'office',NULL,'booked',420,NULL,NULL,'site',NULL,NULL,NULL,'2026-11-10 20:20:00','2026-11-14 20:20:00','2026-11-10 20:11:00','2026-11-14 20:20:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (80,'created','new','2026-11-10 20:11:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (80,'status','new','contacted','2026-11-10 20:20:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (65,'Logan Stone','+15552514735','2026-11-12 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (81,65,'move_out','Old town','booked',340,NULL,NULL,'site','facebook','paid_social','move-out','2026-11-12 19:33:00','2026-11-13 19:33:00','2026-11-12 19:21:00','2026-11-13 19:33:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (81,'created','new','2026-11-12 19:21:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (81,'status','new','contacted','2026-11-12 19:33:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (66,'Alex Ford','+15552522654','2026-11-13 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (82,66,'deep','North side','contacted',NULL,NULL,'2026-11-14','site','google','cpc','brand','2026-11-13 17:23:00','2026-11-13 17:23:00','2026-11-13 17:17:00','2026-11-13 17:23:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (82,'created','new','2026-11-13 17:17:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (82,'status','new','contacted','2026-11-13 17:23:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (67,'Taylor Gray','+15552530573','2026-11-13 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (83,67,'move_out','Old town','booked',340,NULL,NULL,'site','google','cpc','spring-deep','2026-11-13 19:25:00','2026-11-13 19:25:00','2026-11-13 19:22:00','2026-11-13 19:25:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (83,'created','new','2026-11-13 19:22:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (83,'status','new','contacted','2026-11-13 19:25:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (68,'Rowan Wells','+15552538492','2026-11-14 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (84,68,'regular','North side','lost',NULL,'no answer after 3 calls',NULL,'referral',NULL,NULL,NULL,'2026-11-15 03:26:00','2026-11-16 03:26:00','2026-11-14 17:26:00','2026-11-16 03:26:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (84,'created','new','2026-11-14 17:26:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (84,'status','new','contacted','2026-11-15 03:26:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (69,'Riley Hill','+15552546411','2026-11-14 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (85,69,'regular',NULL,'lost',NULL,'no answer after 3 calls',NULL,'site','facebook','paid_social','move-out','2026-11-14 16:40:00','2026-11-17 16:40:00','2026-11-14 16:28:00','2026-11-17 16:40:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (85,'created','new','2026-11-14 16:28:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (85,'status','new','contacted','2026-11-14 16:40:00');
INSERT INTO contacts (id,name,phone,created_at) VALUES (70,'Avery Park','+15552554330','2026-11-15 13:00:00');
INSERT INTO leads (id,contact_id,service,area,status,value,lost_reason,next_action_at,source,utm_source,utm_medium,utm_campaign,first_contact_at,last_touch_at,created_at,updated_at) VALUES (86,70,'office','Riverside','booked',460,NULL,NULL,'site','google','cpc','spring-deep','2026-11-15 16:34:00','2026-11-19 16:34:00','2026-11-15 16:28:00','2026-11-19 16:34:00');
INSERT INTO lead_events (lead_id,kind,to_status,at) VALUES (86,'created','new','2026-11-15 16:28:00');
INSERT INTO lead_events (lead_id,kind,from_status,to_status,at) VALUES (86,'status','new','contacted','2026-11-15 16:34:00');
