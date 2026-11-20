# Speed to lead: what the studies say and how to use it

## Sources
- **Lead Response Management study** (James Oldroyd with InsideSales.com, 2007; widely cited as the "MIT study"). Analysed call logs of web leads across several companies. Reported that the odds of reaching a lead were far higher when the call came within 5 minutes than at 30 minutes, and the odds of qualifying the lead dropped as well. The exact multipliers (often quoted as 100x and 21x) come from that report and vary by how they are framed; quote them only with the source.
- **"The Short Life of Online Sales Leads"**, Harvard Business Review, March 2011, Oldroyd, McElheran and Elkington. Audit of over 2,000 US companies' responses to web leads. Reported that firms contacting a lead within an hour were close to 7 times as likely to qualify it as firms that waited longer, that the average first response took about 42 hours, and that about a quarter of companies never responded.

These are B2B and B2C web leads in general, not local service jobs specifically, and they are old. The direction (faster is better, most companies are slow) has held up; the exact multipliers will not transfer to your business.

## Use your own number
`report.py` prints win rate for leads first contacted inside your target vs later. That is your business, your customers, your prices. Watch it over 8+ weeks. With fewer than 20 leads in either group the script warns that the gap is a hint.

## What the template does for speed
- Alert on every new lead within seconds of the save.
- A second alert if a lead is still `new` after `FIRST_CONTACT_SLA_MIN` minutes, inside work hours only, once per lead.
- Red cards on the board for the same leads.
- `first_contact_at` is set automatically on the first status change, so the speed number needs no extra clicks.

## Common fixes, cheapest first
1. One named person owns new leads per time block. Shared ownership means nobody calls.
2. Turn on alert sound for the bot chat on that person's phone.
3. Cover lunch and the last hour of the day; that is when leads wait longest in most small teams.
4. If you cannot call within the target, send a text right away saying when you will call. Then call at that time.
5. Move `WORK_HOURS` to the hours someone actually answers. A promise on the page that the team cannot keep costs more than no promise.
