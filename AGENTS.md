# AGENTS.md

Notes for coding agents (Claude Code, Codex, Cursor, others) working on this repository.

## What this is

Two things in one repo: a working Cloudflare Worker template in `app/` (landing page, lead API, operator board, cron) and a skill pack in `skills/` that deploys, customises, runs, audits and extends it. Helper scripts are Python 3.8+ standard library only. The app has no runtime npm dependencies; `wrangler` is the only tool it needs.

## Layout

- `app/src/config.js`: every list and setting. `app/src/worker.js`: router, handlers, cron. `app/src/admin.js`: board HTML. `app/src/lib.js`: pure helpers.
- `app/migrations/`: numbered SQL, applied in order. Never edit a migration that may already be applied; add a new one.
- `app/test/run.mjs`, `app/test/bookings.mjs`: offline tests on `node:sqlite` with a D1 shim.
- `skills/crm-*/`: SKILL.md, `references/`, `scripts/`.
- `templates/`: the bookings add-on (migration + module). `examples/`: sample data and `bad-worker.js`, a deliberately insecure Worker for the audit.

## Rules

- SKILL.md frontmatter has only `name` (same as the folder) and `description` (under 1024 characters, says what and "Use when"). Bodies under 500 lines; detail goes to `references/`.
- A new status or service changes `config.js`, a migration and the form together. `check_config.py` must pass.
- A new `/api/` route sits behind the session gate unless it is the public lead POST. `audit_worker.py` must report no high findings on `app/src`.
- No secrets in `wrangler.toml` `[vars]`, in HTML or in tests. Test phone numbers use the +1555 range.
- Examples use invented businesses and people only.
- Run before you finish:

```bash
cd app && node --no-warnings test/run.mjs && node --no-warnings test/bookings.mjs && cd ..
python3 skills/crm-customize/scripts/check_config.py app
python3 skills/crm-hardening/scripts/audit_worker.py app/src
python3 skills/crm-hardening/scripts/audit_worker.py examples/bad-worker.js
python3 skills/crm-bookings/scripts/check_overlaps.py --sqlite examples/bookings-test.sqlite --now 2026-12-01T09:00
python3 skills/crm-customize/scripts/add_field.py --app app --name sqm --type integer --label "Area, m2" --dry-run
```

Expected exit codes: tests 0 (20 passed, 8 passed), check_config 0, audit on app/src 0, audit on bad-worker 1, check_overlaps 1 (one planted overlap), add_field 0.
