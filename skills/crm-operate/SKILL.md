---
name: crm-operate
description: Runs the day-to-day of a mini-crm-site lead board for a small service business, covering the daily call list, status rules, follow-up cadence and lost reasons, plus a weekly report from a D1 export with lead volume, speed to first contact, win rate by source and stale leads. Use when the user asks "what should I do with my leads today", "weekly lead report", "how fast are we calling back", "which source brings customers", "why are we losing leads", "clean up the board", or wants a routine for the person who answers leads.
---

# CRM operate

A CRM earns money only if someone calls fast and follows up. This skill turns the board into a routine and the data into one weekly decision.

## Daily routine (operator, 10 minutes, twice a day)
1. Open `/admin`. Red cards are leads still "new" past the first-contact target (15 minutes by default). Call those first, oldest first.
2. After each call move the card. Rules in [references/pipeline-rules.md](references/pipeline-rules.md). The short version:
   - Reached the person: `contacted`, set a follow-up date if no price yet.
   - Sent a price: `quoted`, set the value and a follow-up date 1 to 2 days out.
   - Date agreed: `booked`, value = agreed price.
   - Work finished and paid: `done`.
   - Not going ahead: `lost` with a reason (required by the server).
   - Bot, wrong number, seller: `spam`.
3. Every open card has a next step: a follow-up date or a note saying what is awaited. A card with neither is how leads rot.
4. Check the morning digest in Telegram: "follow-ups due" is the second call list.

## Weekly report (owner, 15 minutes)
1. Export: `npx wrangler d1 export crm --remote --output crm.sql` (run in `app/`). The file has customer phone numbers: keep it local, delete it after.
2. Run:
   ```bash
   python3 skills/crm-operate/scripts/report.py --dump app/crm.sql
   ```
   Add `--json` to feed another tool. `--sla 10` if your target is 10 minutes. The bundled sample works with `--dump examples/sample-data.sql --now 2026-11-16T12:00`.
3. Read it in this order and pick ONE action for the week:

| Section | Look for | Typical action |
|---|---|---|
| Speed to lead | Median over the target, or "never contacted" above 0 | Fix who answers and when, before touching ads |
| Fast vs slow win rate | A gap between calls inside and outside the target | Shows your own cost of slow calls; with small n it is a hint, not proof |
| By source | A source with leads but zero won after 10+ leads | Cut or fix that source |
| By source | "site (no utm)" is large | Links in ads and posts lack UTM tags, see `tracking-doctor` if you use it |
| Lost reasons | One reason above 30% of lost | Price: show a range on the page. No answer: call faster. Date: offer the next slot on the call |
| Do today | Overdue follow-ups | Clear them before new work |

4. Write the action as one line with a number to check next week: "Callbacks inside 15 min from 52% to 75%: second person covers 12:00 to 14:00."

## Why speed is the first lever
Studies of web leads have found that contacting within minutes beats contacting within hours by a wide margin, and that many companies take a day or never call. Details and sources in [references/speed-to-lead.md](references/speed-to-lead.md). Your own report's fast vs slow line is the number that matters for your business.

## Hard rules
- Never mark a lead `lost` without a reason. The server refuses it; do not work around it with "other".
- Never delete leads to "clean up". Use `spam` or `lost`. The report needs them.
- Never paste exports or phone numbers into public issues, chats or AI tools you do not control.
- Leads that came in by phone or in person: enter them through the site form right after the call (add `?utm_source=phone` to the page URL so the source is recorded), or the report undercounts what works.

## Output
For the weekly report: the five sections from the script, then "This week: <one action> | check: <metric and target>".
