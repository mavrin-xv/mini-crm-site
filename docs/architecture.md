# Architecture

One Cloudflare Worker serves everything. One D1 database holds everything. No build step, no npm dependencies at runtime.

```text
visitor ── GET / ──────────────► static assets (public/index.html), Worker not run
visitor ── POST /api/lead ─────► Worker
                                   honeypot -> Turnstile (optional) -> validate
                                   -> rate limit (hashed IP) -> upsert contact by phone
                                   -> dedup (same contact + service, 30 min)
                                   -> INSERT lead + 'created' event       (D1)
                                   -> 200 {ok:true,id} to the visitor
                                   -> waitUntil: Telegram and/or webhook
                                        -> 'notify_ok' | 'notify_fail' event
operator ─ /admin, /api/* ─────► session gate (signed cookie, Origin check on writes)
                                   board, search, status change, notes, event log
cron */15 ─────────────────────► late-lead alert (work hours, once per lead)
                                   daily digest at DIGEST_HOUR local time
```

## Files
| File | Role |
|---|---|
| `app/src/config.js` | Business settings, services, statuses, hours, form limits. The only file most users edit |
| `app/src/lib.js` | Pure helpers: phone normalising, validation, escaping, session signing, time zones |
| `app/src/worker.js` | Router, handlers, notification, cron |
| `app/src/admin.js` | Login page and the board, served as HTML strings |
| `app/public/index.html` | Landing page with the form |
| `app/migrations/*.sql` | Schema, applied in order by wrangler |
| `app/test/run.mjs` | Offline test of the whole Worker on node:sqlite |
| `app/test/bookings.mjs` | Offline test of the bookings add-on |

## Data model
- `contacts`: one row per phone number.
- `leads`: one row per request; status, value, follow-up date, lost reason, UTM fields, first contact time.
- `lead_events`: append-only log per lead (created, status, note, notify_ok, notify_fail).
- `form_hits`: hashed IP and time for the rate limit, pruned after a day.
- Add-on: `resources`, `bookings`.

## Why these choices
- **Phone as the contact key.** Service customers call and text; email is often missing or mistyped.
- **Save before notify.** The database is the source of truth. Alerts are best effort and logged.
- **Append-only event log.** Who changed what and when, without an audit system. Idea from the activity log in crmkit.
- **Lists in config, enforced by the database.** `config.js` drives the form and board; the CHECK constraint stops a bug from writing a status the board cannot show. `check_config.py` keeps them in sync.
- **No framework.** A small business site should still deploy in five years without upgrading a dependency tree.

## Limits by design
- One operator password. For several named users, add a `users` table and put the user name in the session (the session already carries one).
- The board loads up to 500 leads per view; search covers the rest.
- No email sending. Use the webhook to hand off to a tool that does.
