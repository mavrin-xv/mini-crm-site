# Deploy steps, with what you should see

All commands run in `app/`. `npx wrangler` works without a global install.

## 0. Login (user does this, once)
```bash
npx wrangler login        # opens a browser
npx wrangler whoami       # shows the account name
```

## 1. Offline tests
```bash
node --no-warnings test/run.mjs        # expect: 20 passed
node --no-warnings test/bookings.mjs   # only if you use the bookings add-on: 8 passed
```

## 2. Database
```bash
npx wrangler d1 create crm
```
The output contains a `[[d1_databases]]` block with `database_id = "..."`. Copy only the id into `wrangler.toml` (made from `wrangler.toml.example`).

## 3. Schema
```bash
npx wrangler d1 migrations apply crm --remote
npx wrangler d1 execute crm --remote --command "SELECT name FROM sqlite_master WHERE type='table'"
```
Expect `contacts`, `leads`, `lead_events`, `form_hits` and `d1_migrations`.

## 4. Secrets
```bash
npx wrangler secret put ADMIN_PASSWORD
npx wrangler secret put SESSION_SECRET
npx wrangler secret put TG_BOT_TOKEN
npx wrangler secret put TG_CHAT_ID
npx wrangler secret put NOTIFY_WEBHOOK_URL   # optional
npx wrangler secret put TURNSTILE_SECRET     # optional
npx wrangler secret list                      # names only, values never shown
```
Before the first deploy wrangler may ask to create the Worker; answer yes.

## 5. Deploy
```bash
npx wrangler deploy
```
It prints the URL and `schedule: */15 * * * *`. If the cron line is missing, check `[triggers]` in `wrangler.toml`.

## 6. Smoke test
```bash
python3 ../skills/crm-setup/scripts/smoke_test.py https://mini-crm-site.<you>.workers.dev --password '...'
```
Last line must read `18/18 passed`. Without `--password` only the 10 public checks run.

## 7. Watch it
```bash
npx wrangler tail          # live logs: lead saves, notify errors, cron runs
```

## Backups
```bash
npx wrangler d1 export crm --remote --output backup-$(date +%F).sql
```
D1 also keeps Time Travel (point-in-time restore for the last 30 days on paid plans, 7 days on free, check the current docs). A weekly export you keep yourself is still the only copy you control. The export file contains customer phone numbers: store it like a password.

## Free tier limits that matter here
Numbers from the Cloudflare docs at the time of writing; check the docs before you rely on them.

| Limit | Free | What it means for a lead CRM |
|---|---|---|
| Worker requests | 100,000 / day | Each page view of the landing page served through assets does not run the Worker; form posts and board refreshes do |
| Worker CPU | 10 ms / request | The handlers here do a few queries and no heavy work |
| Cron triggers | 5 per account | The template uses 1 |
| D1 rows read | 5 million / day | The board reads at most 500 leads per refresh |
| D1 rows written | 100,000 / day | A lead is about 4 writes |
| D1 storage | 500 MB per database | Years of leads for a small business |
| Queries per Worker invocation | 50 on free | The lead handler uses under 10 |

The board auto-refreshes every 60 seconds while open. One tab open for 10 hours is about 600 requests and up to 300,000 rows read. Close the tab at night or raise the interval in `src/admin.js` if you get near the read limit.

## Custom domain
In the dashboard: Workers & Pages, your Worker, Settings, Domains & Routes, Add custom domain. The domain must be on the same Cloudflare account. Update `PUBLIC_URL` afterwards.
