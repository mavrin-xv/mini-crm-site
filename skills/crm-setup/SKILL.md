---
name: crm-setup
description: Deploys the mini-crm-site template (landing page with a lead form, lead board, Telegram or webhook alerts, all on one free Cloudflare Worker and D1 database) from zero to a live URL, then proves it works with a smoke test. Use when the user wants a website plus CRM for a small service business, a lead form that lands in a database, "set up the CRM", "deploy mini-crm", "put my leads in D1", "I need a booking/lead site on Cloudflare free tier", or when a deploy of this template fails.
---

# CRM setup

Goal: a live URL where the form saves leads, the operator board needs a password, alerts arrive, and a smoke test passes. Setup is done only when `smoke_test.py` prints all checks green against the live URL. "Deployed" without that is not done.

## Inputs to collect first
Ask once, in one message, and use defaults for anything the user skips:
1. Business name, currency, timezone (IANA, e.g. `America/Chicago`). Default: keep the template values and change later with `crm-customize`.
2. Where alerts go: Telegram bot (token + chat id) or a Slack/Discord-style incoming webhook URL, or both. At least one, or nobody hears about leads.
3. Domain: the free `*.workers.dev` URL is fine to start; a custom domain is a later step.
4. Does the user already have a Cloudflare account and `npx wrangler login` done? If not, they do that themselves. Never create accounts for them.

## Procedure
Work inside the repo's `app/` folder. Full commands with expected output are in [references/deploy-steps.md](references/deploy-steps.md).

1. **Check tools.** `node --version` (22+ for the offline tests), `npx wrangler --version` (4.x). Run the offline tests first: `node --no-warnings test/run.mjs`. Expect `20 passed`. If they fail, stop: the template is broken locally, do not deploy it.
2. **Create the database.** `npx wrangler d1 create crm`. Copy `wrangler.toml.example` to `wrangler.toml` and paste the `database_id`. `wrangler.toml` is git-ignored; keep it that way.
3. **Apply the schema to the remote database.** `npx wrangler d1 migrations apply crm --remote`. Without `--remote` wrangler touches only the local copy and the live site fails with "no such table". This is the most common setup failure.
4. **Set secrets** with `npx wrangler secret put NAME`, one per name:
   - `ADMIN_PASSWORD`: 12+ characters, not reused anywhere.
   - `SESSION_SECRET`: 32 random characters (`python3 -c "import secrets;print(secrets.token_urlsafe(32))"`).
   - `TG_BOT_TOKEN` and `TG_CHAT_ID`, and/or `NOTIFY_WEBHOOK_URL`. How to get them: [references/notifications.md](references/notifications.md).
   Never put a secret in `[vars]`, in the HTML, or in chat logs you paste into issues. The admin returns 503 until both login secrets exist; that is intended.
5. **Set `PUBLIC_URL`** in `[vars]` to the URL you will deploy to, so alert messages link to the board.
6. **Deploy.** `npx wrangler deploy`. Note the URL it prints.
7. **Smoke test the live URL.**
   ```bash
   python3 ../skills/crm-setup/scripts/smoke_test.py https://<name>.<subdomain>.workers.dev --password '<ADMIN_PASSWORD>'
   ```
   It sends test leads with `+1555` numbers and marks them as spam at the end. All checks must pass. Then confirm by hand that the alert reached the phone: the script cannot see Telegram.
8. **Hand over.** Tell the operator: the board URL (`/admin`), that leads older than 15 minutes in "new" trigger an alert in work hours, and that the daily digest arrives at 08:00 local time. Point them to `crm-operate`.

## Local development
`npx wrangler d1 migrations apply crm --local`, create `.dev.vars` with the same secret names, then `npx wrangler dev`. Run the smoke test against `http://127.0.0.1:8787`. Cookies are `Secure`; the script handles that, a browser on plain http may not keep the login. Use `wrangler dev` with the default localhost, which browsers treat as secure.

## Hard rules
- Never deploy if the offline tests fail.
- Never skip `--remote` on migrations for the live database, and never edit an applied migration file.
- Never commit `wrangler.toml` or `.dev.vars`. Run `python3 ../skills/crm-customize/scripts/check_config.py .` before the first commit.
- Free tier is enough for a small business (limits in [references/deploy-steps.md](references/deploy-steps.md)). Do not suggest a paid plan unless a limit is actually hit in the dashboard.

## Failure modes
| Symptom | Cause | Fix |
|---|---|---|
| Live form says "Something went wrong", logs show `no such table` | Migrations applied locally only | `npx wrangler d1 migrations apply crm --remote` |
| `/admin` returns 503 | `ADMIN_PASSWORD` or `SESSION_SECRET` missing or shorter than 16 chars | Set both secrets, redeploy not needed |
| Leads saved, no alert | Wrong chat id, bot never started by the user, or webhook URL typo | Board shows `notify_fail` in the lead's event log with the error text |
| Login works then logs out at once | Opened over plain http on a non-localhost host | Use https (workers.dev is https) |
| Alerts at night | Wrong `BUSINESS.timezone` | Set the IANA zone in `src/config.js`, redeploy |

## Output
Report: live URL, board URL, which alert channel was verified by a real message, smoke test summary line, and what is left (custom domain, Turnstile, customisation).
