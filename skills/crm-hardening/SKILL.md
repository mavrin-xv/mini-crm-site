---
name: crm-hardening
description: Audits a small lead or booking site built on a Cloudflare Worker (this template or any hand-rolled one) for the mistakes that leak customer data or lose leads, such as public read endpoints, default passwords, tokens shipped in HTML, SQL built from strings, unescaped alert messages, missing rate limits and notify-before-save. It runs a static scan plus a no-login live probe and gives a fix list ordered by severity. Use when the user asks "is my CRM secure", "audit the worker", "security check before launch", "can anyone see my leads", "QA the booking site", after any change to auth or API routes, or before handing a site to a client.
---

# CRM hardening

Small business sites get hand-written Workers, and the same handful of mistakes shows up again and again: an `/api/bookings` GET added "for the admin page" that never checks a session, a password with a fallback in code, a write token pasted into the admin HTML. Every one of them leaks customer names and phone numbers to anyone who guesses a URL. This skill finds them before someone else does.

## Procedure
1. **Static scan** of the Worker source:
   ```bash
   python3 skills/crm-hardening/scripts/audit_worker.py app/src
   ```
   Twelve checks, H01 to H12, each with a severity and a fix. Exit 1 on any high. To see what each finding looks like, run it on `examples/bad-worker.js` (10 findings, 4 high).
2. **Live probe** without a login, against the deployed URL (or `wrangler dev`):
   ```bash
   python3 skills/crm-hardening/scripts/audit_worker.py --probe https://your-site.workers.dev
   ```
   Every data path must answer 401, 403 or 404. A 200 with JSON is a leak (P01). A 5xx on a bad body is P02.
3. **Manual checklist**: walk [references/qa-checklist.md](references/qa-checklist.md). The script cannot see logic bugs such as a status list that differs between two queries or an operator who can change a lead to a status the board cannot show. The checklist covers those.
4. **Fix in severity order.** High first. After each fix, rerun the scan and the offline tests (`node --no-warnings test/run.mjs`).
5. **Re-probe the live site** after deploy. A fix is done when the live probe is clean, not when the code looks right.

## The rules the template follows (keep them when you change it)
1. **Every route under `/api/` needs a session**, except the public lead POST, login, logout and health. The gate is one function at the top of the router, not a check inside each handler. New routes are closed by default.
2. **No default credentials.** Missing `ADMIN_PASSWORD` or `SESSION_SECRET` means the admin answers 503. Never `|| 'admin'`.
3. **No secrets in HTML or JS sent to the browser.** The board uses the session cookie; it never needs a token.
4. **Bind every SQL value** with `?`. Only fixed fragments written in code (placeholder lists, column names from a whitelist) are joined into SQL text.
5. **Validate on the server** with the same rules as the form, plus lengths, dates not in the past, service and status from the config lists only.
6. **Save first, notify second.** The lead is in the database before the visitor sees "thanks"; the alert runs in `ctx.waitUntil` and its result is logged.
7. **Escape everything** that goes into an HTML-mode alert or the board. The board renders with `textContent`.
8. **Dedup and rate limit** the public POST: same phone and service within the window returns the existing lead; 5 posts per IP per 10 minutes, IP stored hashed.
9. **One status constant** per meaning (open, won, occupying a slot), imported everywhere.
10. **Cookies**: `HttpOnly; Secure; SameSite=Strict`, signed, with expiry. Mutations check `Origin`.

## Hard rules
- A high finding blocks launch. No "we will fix it later" for P01 or H01 to H05.
- Never test the probe against a site you do not own or have permission to test.
- If a leak was live, assume the data was read: rotate secrets, and tell the business owner so they can decide on notifying customers under their local law.

## Output
```
Static: N findings (H high). Live probe: clean | LEAKS on <paths>.
Fix list (ordered):
1. [HIGH] H0x file:line, what, fix
...
Checklist items not covered by the scan: <list with pass/fail>
Verdict: SHIP | FIX FIRST
```
