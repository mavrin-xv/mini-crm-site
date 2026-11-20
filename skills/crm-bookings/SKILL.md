---
name: crm-bookings
description: Adds time-slot booking to the mini-crm-site template (crews, rooms, vans, cabins) with a hold that expires, a 409 on overlapping bookings, one shared list of statuses that occupy a slot, and a checker that finds double bookings in an export. Use when the user wants customers or the operator to book a date or time, "add bookings", "add a calendar", "stop double bookings", "we got booked twice for the same slot", "hold a slot until payment", or wants to audit an existing booking table for overlaps.
---

# CRM bookings

Leads answer "who wants what". Bookings answer "which resource is busy when". The add-on is off by default: many service businesses only need leads and a phone call. Add it when the same crew, room or vehicle gets double-booked, or when customers pick a slot themselves.

## The one rule
There is exactly one list of statuses that occupy a slot: `OCCUPYING_STATUSES` in `templates/bookings.js` (`held`, `confirmed`, `paid`). The overlap guard, the availability query, the calendar and any report import it. The classic double-booking bug is a second query written by hand with `('new','confirmed')` that predates the `paid` status: paid bookings look free and get sold again.

## Install
1. Copy `templates/0002_bookings.sql` to `app/migrations/` (renumber if 0002 is taken) and `templates/bookings.js` to `app/src/bookings.js`.
2. Run the add-on tests from `app/`: `node --no-warnings test/bookings.mjs`. Expect `8 passed`. The test imports from `templates/`; point it at `src/bookings.js` if you edit your copy.
3. Apply: `npx wrangler d1 migrations apply crm --local`, then `--remote` when the routes below work in `wrangler dev`.
4. Add resources: `npx wrangler d1 execute crm --remote --command "INSERT INTO resources (name) VALUES ('Crew A'), ('Crew B')"`.
5. Wire routes in `app/src/worker.js`, all behind the existing session gate unless you want public self-booking:
   - `POST /api/bookings` calls `createBooking(env.DB, body)`; return its status code (400, 409) as is.
   - `PATCH /api/bookings/:id` calls `setBookingStatus`.
   - `GET /api/bookings?from=&to=` for the operator calendar.
   - In `runCron`, call `releaseExpiredHolds(env.DB, now)`.
6. Public self-booking (optional): expose only a free-slots endpoint that returns times, never names or phones, and a POST that creates a `held` booking tied to a new lead. Run `crm-hardening`'s probe after.

## How the guard works
- Ranges are half-open `[start, end)`: 09:00 to 12:00 and 12:00 to 14:00 do not clash.
- `held` bookings expire after `HOLD_MINUTES` (30). An expired hold stops counting at once; the cron also marks it `cancelled`.
- `createBooking` checks, inserts, then checks again. If two requests raced and both inserted, the later row is cancelled and that caller gets 409.
- Moving a booking from `cancelled` back to `confirmed` re-checks the slot.
- `capacity` on a resource allows N parallel bookings (a team of 3 cleaners as one resource with capacity 3).

Details and edge cases: [references/booking-rules.md](references/booking-rules.md).

## Audit an existing booking table
```bash
npx wrangler d1 export crm --remote --output crm.sql
python3 skills/crm-bookings/scripts/check_overlaps.py --dump crm.sql
python3 skills/crm-bookings/scripts/check_overlaps.py --dump crm.sql --occupying held,confirmed,paid,done
```
The first run uses the statuses you believe occupy a slot. The second widens the list. Extra pairs in the second run point to a status some code path treats as free. The repo ships a planted example: `node --no-warnings test/bookings.mjs` writes `examples/bookings-test.sqlite` with one double booking; `check_overlaps.py --sqlite examples/bookings-test.sqlite --now 2026-12-01T09:00` finds it.

## Hard rules
- Never write a status list by hand in a query. Import the constant.
- Store times in UTC; convert to local only for display.
- A 409 goes back to the person with the next free slot, not a generic error.
- Run `check_overlaps.py` after any change to booking code and weekly while the add-on is new.
