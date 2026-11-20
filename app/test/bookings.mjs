// Offline test of the optional bookings add-on (templates/0002_bookings.sql + templates/bookings.js).
// Run: node --no-warnings test/bookings.mjs
// Writes ../../examples/bookings-test.sqlite so check_overlaps.py can be tried on a known-bad DB.
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { createBooking, setBookingStatus, releaseExpiredHolds, overlapping } from '../../templates/bookings.js';

const file = new URL('../../examples/bookings-test.sqlite', import.meta.url);
rmSync(file, { force: true });
const db = new DatabaseSync(fileURLToPath(file));
db.exec(readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8'));
db.exec(readFileSync(new URL('../../templates/0002_bookings.sql', import.meta.url), 'utf8'));
db.exec("INSERT INTO resources (name) VALUES ('Crew A'), ('Crew B')");

const stmt = (sql, args = []) => ({
  bind: (...a) => stmt(sql, a),
  first: async () => db.prepare(sql).get(...args) ?? null,
  all: async () => ({ results: db.prepare(sql).all(...args) }),
  run: async () => ({ meta: { changes: db.prepare(sql).run(...args).changes } }),
});
const D1 = { prepare: (sql) => stmt(sql) };
const now = new Date('2026-12-01T09:00:00Z');

let passed = 0;
async function t(name, fn) {
  try { await fn(); passed++; console.log('PASS', name); } catch (e) { console.log('FAIL', name, '\n  ', e.message); process.exitCode = 1; }
}

let first;
await t('booking a free slot', async () => {
  const r = await createBooking(D1, { resource_id: 1, start_at: '2026-12-03 09:00:00', end_at: '2026-12-03 12:00:00' }, now);
  assert.ok(r.ok); first = r.id;
});
await t('overlap is refused with 409', async () => {
  const r = await createBooking(D1, { resource_id: 1, start_at: '2026-12-03 11:00:00', end_at: '2026-12-03 13:00:00' }, now);
  assert.equal(r.status, 409);
});
await t('touching ends do not overlap', async () => {
  assert.ok((await createBooking(D1, { resource_id: 1, start_at: '2026-12-03 12:00:00', end_at: '2026-12-03 14:00:00' }, now)).ok);
});
await t('other resource is independent', async () => {
  assert.ok((await createBooking(D1, { resource_id: 2, start_at: '2026-12-03 09:00:00', end_at: '2026-12-03 12:00:00' }, now)).ok);
});
await t('paid still occupies the slot', async () => {
  assert.ok((await setBookingStatus(D1, first, 'paid', now)).ok);
  const r = await createBooking(D1, { resource_id: 1, start_at: '2026-12-03 10:00:00', end_at: '2026-12-03 10:30:00' }, now);
  assert.equal(r.status, 409);
});
await t('bad range is a 400', async () => {
  assert.equal((await createBooking(D1, { resource_id: 1, start_at: '2026-12-03 12:00:00', end_at: '2026-12-03 11:00:00' }, now)).status, 400);
});
await t('expired hold frees the slot and cron releases it', async () => {
  const r = await createBooking(D1, { resource_id: 2, start_at: '2026-12-05 09:00:00', end_at: '2026-12-05 10:00:00' }, now);
  const later = new Date(now.getTime() + 31 * 60000);
  assert.equal((await overlapping(D1, 2, '2026-12-05 09:00:00', '2026-12-05 10:00:00', null, later)).length, 0);
  assert.ok((await releaseExpiredHolds(D1, later)) >= 1);
  assert.equal(db.prepare('SELECT status FROM bookings WHERE id=?').get(r.id).status, 'cancelled');
});
await t('re-confirming a cancelled booking re-checks the slot', async () => {
  const r = await createBooking(D1, { resource_id: 2, start_at: '2026-12-06 09:00:00', end_at: '2026-12-06 10:00:00' }, now);
  await setBookingStatus(D1, r.id, 'cancelled', now);
  assert.ok((await createBooking(D1, { resource_id: 2, start_at: '2026-12-06 09:30:00', end_at: '2026-12-06 11:00:00' }, now)).ok);
  assert.equal((await setBookingStatus(D1, r.id, 'confirmed', now)).status, 409);
});

// Plant the classic bug for check_overlaps.py: a second 'paid' row written by a code path
// that used its own status list.
db.exec("INSERT INTO bookings (resource_id, start_at, end_at, status) VALUES (1, '2026-12-03 10:00:00', '2026-12-03 11:00:00', 'paid')");
db.close();
console.log(`\n${passed} passed${process.exitCode ? ', some FAILED' : ''}`);
