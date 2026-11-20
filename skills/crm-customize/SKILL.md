---
name: crm-customize
description: Adapts the mini-crm-site template to a specific service business (services, pipeline statuses, form fields, timezone, work hours, landing page copy, alert text) without breaking the database or the board, and verifies every change with a consistency check and the offline tests. Use when the user says "change the services", "add a field to the form", "rename the statuses", "make it for my plumbing / cleaning / repair / tutoring business", "add a column", "change the landing page", or after crm-setup when the template still shows the sample business.
---

# CRM customize

The template keeps a few lists in more than one place on purpose (code, database, form). Customising means changing all copies of a list together, then proving they agree. `check_config.py` and the offline tests are the proof. A change is done when both are green and the change is deployed.

## What lives where
| Thing | File | Also must match |
|---|---|---|
| Business name, currency, timezone | `app/src/config.js` `BUSINESS` | Landing page text in `app/public/index.html` |
| Services | `config.js` `SERVICES` | `<select name="service">` options in `index.html` |
| Statuses and their order on the board | `config.js` `STATUSES` | `CHECK (status IN ...)` in the migrations |
| Which statuses are open / won | `OPEN_STATUSES`, `WON_STATUSES` | Only keys from `STATUSES`; `crm-operate/scripts/report.py` constants `OPEN` and `WON` |
| Work hours, digest hour, first-contact target | `WORK_HOURS`, `DIGEST_HOUR`, `FIRST_CONTACT_SLA_MIN` | Hand-over notes for the operator |
| Form limits, rate limit, dedup window | `FORM` | Nothing |
| Alert text | `formatLeadMessage` in `app/src/lib.js` | Escape every value |

## Procedure
1. **Write the change list first** and show it to the user in plain words: "Services become: drain cleaning, water heater, leak repair, emergency. Status 'quoted' renamed to 'estimate sent'. New field: property type." Confirm before editing.
2. **Labels vs keys.** Change the label (`deep: 'Deep clean'`) freely. Keys (`deep`) are stored in the database: renaming a key needs a data migration. Prefer keeping old keys with new labels.
3. **Services**: edit `SERVICES` and the `<option>` list together. Keys are lowercase snake_case.
4. **New field**: run
   ```bash
   python3 skills/crm-customize/scripts/add_field.py --app app --name property_type --type text --label "Property type"
   ```
   It writes the next numbered migration and prints each file and line to edit (form, validation, insert, board view, alert, test). Make every edit it lists. Validation is a human decision: max length, allowed values, required or not.
5. **Statuses**: adding or removing a status changes the database `CHECK` constraint. SQLite cannot alter a CHECK in place; it needs a table rebuild migration. Follow [references/schema-changes.md](references/schema-changes.md) exactly. Renaming only the label needs no migration.
6. **Landing page**: edit `app/public/index.html`. Keep the form field names, the hidden `website` honeypot, the hidden `utm_*` inputs and the script that posts to `/api/lead`. Copy rules in [references/landing-copy.md](references/landing-copy.md).
7. **Verify**:
   ```bash
   python3 skills/crm-customize/scripts/check_config.py app
   cd app && node --no-warnings test/run.mjs
   ```
   Both must pass. If you changed services or statuses, update the test data in `test/run.mjs` (it uses `deep` and `office`).
8. **Ship**: `npx wrangler d1 migrations apply crm --local`, try it in `wrangler dev`, then `--remote`, then `npx wrangler deploy`, then the smoke test from `crm-setup`.

## Hard rules
- Never edit a migration that has been applied anywhere. Add a new one.
- Never drop a column or table holding leads without an export first (`npx wrangler d1 export crm --remote --output before-change.sql`).
- Apply migrations to remote before deploying code that reads the new column, or the live site breaks between the two steps.
- Every new free-text field is validated server side with a max length, even if the form has `maxlength`. The form is not a security boundary.
- New fields shown on the board use `textContent`, never `innerHTML`.

## Failure modes
| Symptom | Cause |
|---|---|
| Status change on the board gives 500 | Status key not in the database CHECK: rebuild migration missing |
| Form says "Pick a service" for a valid choice | `<option value>` not in `SERVICES` |
| Report shows 0 won | `WON_STATUSES` and `report.py` `WON` disagree after a rename |
| New field always empty in the database | Added to the form and migration but not to `validateLead` or the INSERT |
