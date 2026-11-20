// Optional add-on: booking helpers for templates/0002_bookings.sql.
// Copy to app/src/bookings.js and import from worker.js. Not wired by default.

// The ONE list of statuses that hold a slot. Import it everywhere; never retype it.
export const OCCUPYING_STATUSES = ['held', 'confirmed', 'paid'];
export const BOOKING_STATUSES = ['held', 'confirmed', 'paid', 'cancelled', 'done'];
export const HOLD_MINUTES = 30;

const placeholders = (n) => Array(n).fill('?').join(',');
const TS = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/;

// Bookings on this resource that overlap [start, end). Half-open: touching ends do not overlap.
// Expired holds do not count.
export async function overlapping(db, resourceId, start, end, excludeId = null, now = new Date()) {
  const nowTs = now.toISOString().slice(0, 19).replace('T', ' ');
  const sql = `SELECT id, start_at, end_at, status FROM bookings
    WHERE resource_id = ? AND status IN (${placeholders(OCCUPYING_STATUSES.length)})
      AND start_at < ? AND end_at > ?
      AND NOT (status = 'held' AND hold_until IS NOT NULL AND hold_until <= ?)
      AND (? IS NULL OR id != ?)`;
  const { results } = await db.prepare(sql)
    .bind(resourceId, ...OCCUPYING_STATUSES, end, start, nowTs, excludeId, excludeId).all();
  return results;
}

// Create a booking or return { ok:false, status:409 }. Check and insert run back to back;
// on D1 a single Worker request is serialised per database, but two requests can still race.
// The final guard is the re-check after insert: if a second overlapping row appeared, the
// later one is cancelled.
export async function createBooking(db, b, now = new Date()) {
  if (!TS.test(b.start_at) || !TS.test(b.end_at) || b.end_at <= b.start_at)
    return { ok: false, status: 400, error: 'start_at and end_at must be YYYY-MM-DD HH:MM:SS, end after start' };
  const res = await db.prepare('SELECT capacity, active FROM resources WHERE id = ?').bind(b.resource_id).first();
  if (!res || !res.active) return { ok: false, status: 400, error: 'unknown resource' };
  if ((await overlapping(db, b.resource_id, b.start_at, b.end_at, null, now)).length >= res.capacity)
    return { ok: false, status: 409, error: 'slot taken' };
  const holdUntil = new Date(now.getTime() + HOLD_MINUTES * 60000).toISOString().slice(0, 19).replace('T', ' ');
  const row = await db.prepare(`INSERT INTO bookings (resource_id, lead_id, start_at, end_at, status, hold_until, price, note)
    VALUES (?, ?, ?, ?, 'held', ?, ?, ?) RETURNING id`)
    .bind(b.resource_id, b.lead_id ?? null, b.start_at, b.end_at, holdUntil, b.price ?? null, b.note ?? null).first();
  const clash = await overlapping(db, b.resource_id, b.start_at, b.end_at, null, now);
  if (clash.length > res.capacity && Math.max(...clash.map((c) => c.id)) === row.id) {
    await db.prepare("UPDATE bookings SET status = 'cancelled', note = 'lost a race' WHERE id = ?").bind(row.id).run();
    return { ok: false, status: 409, error: 'slot taken' };
  }
  return { ok: true, id: row.id, hold_until: holdUntil };
}

// Status change with the same guard: moving a cancelled booking back to confirmed must re-check.
export async function setBookingStatus(db, id, status, now = new Date()) {
  if (!BOOKING_STATUSES.includes(status)) return { ok: false, status: 400, error: 'bad status' };
  const b = await db.prepare('SELECT * FROM bookings WHERE id = ?').bind(id).first();
  if (!b) return { ok: false, status: 404, error: 'not found' };
  if (OCCUPYING_STATUSES.includes(status) && !OCCUPYING_STATUSES.includes(b.status)) {
    const cap = (await db.prepare('SELECT capacity FROM resources WHERE id = ?').bind(b.resource_id).first()).capacity;
    if ((await overlapping(db, b.resource_id, b.start_at, b.end_at, id, now)).length >= cap)
      return { ok: false, status: 409, error: 'slot taken' };
  }
  await db.prepare("UPDATE bookings SET status = ?, hold_until = CASE WHEN ? = 'held' THEN hold_until ELSE NULL END, updated_at = datetime('now') WHERE id = ?")
    .bind(status, status, id).run();
  return { ok: true };
}

// Cron: release holds that expired. Call from runCron().
export async function releaseExpiredHolds(db, now = new Date()) {
  const nowTs = now.toISOString().slice(0, 19).replace('T', ' ');
  const r = await db.prepare("UPDATE bookings SET status = 'cancelled', note = COALESCE(note,'') || ' hold expired' WHERE status = 'held' AND hold_until <= ?")
    .bind(nowTs).run();
  return r.meta.changes;
}
