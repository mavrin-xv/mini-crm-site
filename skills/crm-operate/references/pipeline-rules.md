# Pipeline rules

## Statuses
| Status | Means | Required |
|---|---|---|
| `new` | Came in, nobody talked to the person yet | Nothing. Moving out of `new` sets `first_contact_at` once |
| `contacted` | Talked to them, no price yet | Follow-up date or a note on what is awaited (photos, address) |
| `quoted` | Price sent | Value, follow-up date |
| `booked` | Date and price agreed | Value (the agreed price) |
| `done` | Work done and paid | Final value if it changed |
| `lost` | Not going ahead | Lost reason |
| `spam` | Not a real request | Nothing |

`booked` and `done` count as won in the report. `new`, `contacted`, `quoted`, `booked` count as open.

## Follow-up cadence
A plain cadence that fits most local service jobs. Adjust to your sales cycle.

| Situation | Next touch |
|---|---|
| No answer on first call | Call again in 30 to 60 minutes, then a text, then next morning |
| Contacted, waiting for details | Next working day |
| Quoted | Day 1 or 2, then day 4, then day 7. After the third touch with no reply: `lost`, reason "no reply" |
| Booked | Reminder the day before the job |
| Done | Ask for a review within 2 days |

Set `next_action_at` on the board after every touch. The digest lists what is due.

## Lost reasons
Free text, but keep a short, fixed vocabulary so the report can count them:
`price`, `no reply`, `date not available`, `went with someone else`, `out of area`, `not a service we do`, `changed mind`.

A reason given by the customer beats a guess. Ask: "Can I ask what made you decide against it?"

## Value
Whole currency units, no cents. Quoted value on `quoted`, agreed price on `booked`, final on `done`. The report sums `value` of won leads by source.

## Repeat customers
Same phone number = same contact. A second request for a different service is a new lead under the same contact. The same request twice within 30 minutes is a duplicate and is merged automatically.
