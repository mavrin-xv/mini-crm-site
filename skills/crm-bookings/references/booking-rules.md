# Booking rules and edge cases

## Statuses
| Status | Occupies slot | Meaning |
|---|---|---|
| `held` | yes, until `hold_until` | Slot reserved while the customer confirms or pays |
| `confirmed` | yes | Agreed, not paid |
| `paid` | yes | Paid in advance |
| `done` | no | Job finished; the time is in the past |
| `cancelled` | no | Released |

`done` is not occupying because the slot is in the past. If your business marks jobs `done` before the end time (crew finished early, still on site), add `done` to `OCCUPYING_STATUSES`.

## Overlap test
Two ranges `[a1, a2)` and `[b1, b2)` overlap when `a1 < b2 AND b1 < a2`. With text timestamps in `YYYY-MM-DD HH:MM:SS` format SQLite compares them correctly as strings. Never mix formats (`T` separator, time zones, missing seconds): string compare breaks silently. `createBooking` rejects other formats with 400.

## Races
D1 does not offer `SELECT ... FOR UPDATE`. Two customers booking the last slot at the same second can both pass the first check. The template handles it by checking again after the insert and cancelling the later row. For high-traffic public booking, put a Durable Object in front of each resource; for a small business the re-check is enough.

## Buffers
Travel time between jobs: store it in the booking (end the range 30 minutes after the job really ends) rather than in the overlap query. The query stays simple and the calendar shows the real busy time.

## Time zones and daylight saving
Store UTC. Convert at the edges (form input, calendar display) with the business timezone from `config.js`. A slot at 09:00 local is a different UTC hour in winter and summer; generate free slots per day in local time, then convert each to UTC.

## Holds and payment
If you take a deposit through a payment link, keep the booking `held` until the payment webhook arrives, then `paid`. Set `HOLD_MINUTES` longer than the payment page timeout. If the webhook comes after the hold expired and the slot is now taken, refund and tell the customer: that case must be handled by a person, not silently confirmed.

## What to show the public
Free slots only: start and end times per resource type. Never names, phones, notes, or which other customer holds a slot.
