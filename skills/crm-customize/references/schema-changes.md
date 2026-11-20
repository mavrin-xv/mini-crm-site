# Schema changes on D1

D1 is SQLite. `ALTER TABLE ... ADD COLUMN` works. Changing a CHECK constraint, a column type or a NOT NULL does not: you rebuild the table.

## Add a nullable column (safe, use add_field.py)
```sql
ALTER TABLE leads ADD COLUMN property_type TEXT;
```
Old rows get NULL. Nothing else changes.

## Add or remove a status (table rebuild)
Example: add `scheduled` between `quoted` and `booked`. Write `app/migrations/0003_status_scheduled.sql`:

```sql
-- Rebuild leads with a new status list. Data is copied as-is.
PRAGMA defer_foreign_keys = true;

CREATE TABLE leads_new (
  -- copy every column definition from the current leads table, with the new CHECK:
  -- status TEXT NOT NULL DEFAULT 'new'
  --   CHECK (status IN ('new','contacted','quoted','scheduled','booked','done','lost','spam')),
  ...
);

INSERT INTO leads_new SELECT * FROM leads;
DROP TABLE leads;
ALTER TABLE leads_new RENAME TO leads;

-- recreate the indexes from 0001_init.sql (they were dropped with the old table)
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(status);
...
```

Rules for the rebuild:
1. Copy the column list from the newest definition, in the same order, so `SELECT *` lines up. If you added columns in later migrations they go at the end, in the order they were added. Safer: list the columns by name in both the INSERT and the SELECT.
2. `PRAGMA defer_foreign_keys = true` lets `lead_events.lead_id` keep pointing at ids while the table is swapped. Ids are preserved by the copy.
3. Recreate every index on `leads`.
4. When removing a status, first move rows off it in the same migration: `UPDATE leads SET status = 'lost' WHERE status = 'old_status';` before the copy.
5. Export first: `npx wrangler d1 export crm --remote --output before-0003.sql`.
6. Run on local, run the offline tests (they apply all migrations to an empty DB), click through the board in `wrangler dev`, then `--remote`.

Then update `STATUSES` (and `OPEN_STATUSES` / `WON_STATUSES` if needed) in `config.js` and `OPEN` / `WON` in `skills/crm-operate/scripts/report.py`. Run `check_config.py`.

## Rename a key
Two steps in one migration: rebuild with a CHECK that allows both old and new keys, `UPDATE` rows to the new key, then a second rebuild later that drops the old key. Or keep the old key and change only the label. The second is almost always the right call.

## Never
- Edit `0001_init.sql` after it was applied. Wrangler records applied file names in `d1_migrations` and will not re-run it; your local and remote schemas silently drift.
- Run a rebuild on remote without the export.
- Deploy code that writes a new status before the migration that allows it is applied remotely.
