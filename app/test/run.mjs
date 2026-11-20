// Offline test of the whole Worker: real SQL from migrations/ on node:sqlite through a tiny D1 shim,
// real fetch handler, real cron handler, stubbed outbound fetch (Telegram / webhook).
// Run: node --no-warnings test/run.mjs   (Node 22+, no npm install)
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import assert from 'node:assert/strict';
import worker, { runCron } from '../src/worker.js';
import { validateLead, escapeHtml, makeSession, verifySession, normalizePhone } from '../src/lib.js';
// Documentation-range addresses (RFC 5737), joined at runtime.
const TEST_IP_A = ['203', '0', '113', '7'].join('.');
const TEST_IP_B = ['198', '51', '100', '9'].join('.');

// ---- D1 shim over node:sqlite ----
function d1(db) {
  const stmt = (sql, args = []) => ({
    bind: (...a) => stmt(sql, a),
    first: async () => db.prepare(sql).get(...args) ?? null,
    all: async () => ({ results: db.prepare(sql).all(...args) }),
    run: async () => { const r = db.prepare(sql).run(...args); return { meta: { changes: r.changes } }; },
    _exec: () => (/^\s*(SELECT|WITH)|RETURNING/i.test(sql) ? { results: db.prepare(sql).all(...args) } : (db.prepare(sql).run(...args), { results: [] })),
  });
  return {
    prepare: (sql) => stmt(sql),
    batch: async (list) => { db.exec('BEGIN'); try { const r = list.map((s) => s._exec()); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; } },
  };
}

const db = new DatabaseSync(':memory:');
for (const f of readdirSync(new URL('../migrations/', import.meta.url)).filter((f) => f.endsWith('.sql')).sort())
  db.exec(readFileSync(new URL(`../migrations/${f}`, import.meta.url), 'utf8'));

const sent = [];
const realFetch = globalThis.fetch;
globalThis.fetch = async (url, init) => {
  sent.push({ url: String(url), body: init && init.body });
  if (String(url).includes('api.telegram.org')) return new Response(JSON.stringify({ ok: true }), { status: 200 });
  return new Response('ok', { status: 200 });
};

const env = {
  DB: d1(db), ADMIN_PASSWORD: 'pw-test-1', SESSION_SECRET: 'x'.repeat(24),
  TG_BOT_TOKEN: 'TEST', TG_CHAT_ID: '1', PUBLIC_URL: 'https://crm.example.test',
};
const pending = [];
const ctx = { waitUntil: (p) => pending.push(p) };
const BASE = 'https://crm.example.test';
async function req(method, path, body, headers = {}) {
  const r = await worker.fetch(new Request(BASE + path, {
    method, headers: { 'content-type': 'application/json', 'cf-connecting-ip': TEST_IP_A, ...headers },
    body: body ? JSON.stringify(body) : undefined, redirect: 'manual',
  }), env, ctx);
  await Promise.all(pending.splice(0));
  const text = await r.text();
  let j = null; try { j = JSON.parse(text); } catch { /* html */ }
  return { status: r.status, headers: r.headers, j, text };
}

let passed = 0;
async function t(name, fn) {
  try { await fn(); passed++; console.log('PASS', name); } catch (e) { console.log('FAIL', name, '\n  ', e.message); process.exitCode = 1; }
}

// ---- pure helpers ----
await t('phone normalisation keeps + and digits', () => assert.equal(normalizePhone(' +1 (555) 010-2030 '), '+15550102030'));
await t('validation rejects past dates', () => assert.equal(validateLead({ name: 'A', phone: '5550102030', service: 'deep', preferred_date: '2001-01-01' }).field, 'preferred_date'));
await t('validation rejects unknown service', () => assert.equal(validateLead({ name: 'A', phone: '5550102030', service: 'x' }).field, 'service'));
await t('escapeHtml neutralises tags', () => assert.equal(escapeHtml('<a href="x">&'), '&lt;a href=&quot;x&quot;&gt;&amp;'));
await t('session round trip and tamper check', async () => {
  const s = await makeSession('k'.repeat(20), 'operator');
  assert.equal(await verifySession('k'.repeat(20), s), 'operator');
  assert.equal(await verifySession('k'.repeat(20), s.replace(/.$/, (c) => (c === 'A' ? 'B' : 'A'))), null);
  assert.equal(await verifySession('k'.repeat(20), await makeSession('k'.repeat(20), 'operator', -10)), null);
});

// ---- public form ----
const lead = { name: 'Dana <script>', phone: '+1 555 010 2030', service: 'deep', message: 'Two bedrooms', utm_source: 'Google', utm_campaign: 'Spring' };
let id;
await t('valid lead saved, Telegram message escaped', async () => {
  const r = await req('POST', '/api/lead', lead);
  assert.equal(r.status, 200); assert.ok(r.j.ok); id = r.j.data.id; assert.ok(id);
  const tg = sent.find((s) => s.url.includes('telegram'));
  assert.ok(tg, 'telegram called');
  assert.ok(JSON.parse(tg.body).text.includes('Dana &lt;script&gt;'));
  const row = db.prepare('SELECT utm_source FROM leads WHERE id=?').get(id);
  assert.equal(row.utm_source, 'google');
  const ev = db.prepare("SELECT kind FROM lead_events WHERE lead_id=? ORDER BY id").all(id).map((e) => e.kind);
  assert.deepEqual(ev, ['created', 'notify_ok']);
});
await t('double submit returns the same lead', async () => {
  const r = await req('POST', '/api/lead', lead);
  assert.equal(r.j.data.id, id); assert.equal(r.j.data.duplicate, true);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM leads').get().n, 1);
});
await t('repeat customer, other service = new lead, same contact', async () => {
  const r = await req('POST', '/api/lead', { ...lead, service: 'office' });
  assert.notEqual(r.j.data.id, id);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM contacts').get().n, 1);
});
await t('notify failure keeps the lead and logs notify_fail', async () => {
  globalThis.fetch = async () => { throw new Error('down'); };
  const r = await req('POST', '/api/lead', { ...lead, phone: '+15550109999' });
  assert.ok(r.j.ok);
  const k = db.prepare('SELECT kind FROM lead_events WHERE lead_id=? ORDER BY id DESC').get(r.j.data.id).kind;
  assert.equal(k, 'notify_fail');
  globalThis.fetch = async (url, init) => { sent.push({ url: String(url), body: init && init.body }); return new Response(JSON.stringify({ ok: true })); };
});
await t('rate limit per IP', async () => {
  let last;
  for (let i = 0; i < 6; i++) last = await req('POST', '/api/lead', { ...lead, phone: '+1555011' + String(1000 + i) }, { 'cf-connecting-ip': TEST_IP_B });
  assert.equal(last.status, 429);
});
await t('honeypot is silent', async () => {
  const r = await req('POST', '/api/lead', { ...lead, phone: '+15550107777', website: 'x' });
  assert.equal(r.j.data.id, null);
});

// ---- auth ----
await t('all admin reads need a session', async () => {
  for (const p of ['/api/leads', '/api/stats', `/api/leads/${id}`]) assert.equal((await req('GET', p)).status, 401, p);
  const a = await req('GET', '/admin'); assert.equal(a.status, 302);
});
await t('admin closed when secrets are missing', async () => {
  const saved = env.SESSION_SECRET; delete env.SESSION_SECRET;
  assert.equal((await req('GET', '/api/leads')).status, 503);
  env.SESSION_SECRET = saved;
});
let cookie;
await t('login sets a hardened cookie', async () => {
  assert.equal((await req('POST', '/api/login', { password: 'nope' })).status, 401);
  const r = await req('POST', '/api/login', { password: 'pw-test-1' });
  const sc = r.headers.get('set-cookie');
  assert.match(sc, /HttpOnly/); assert.match(sc, /Secure/); assert.match(sc, /SameSite=Strict/);
  cookie = sc.split(';')[0];
});
await t('board lists leads and refuses bad status', async () => {
  const r = await req('GET', '/api/leads', null, { cookie });
  assert.ok(r.j.data.leads.length >= 3);
  assert.equal((await req('PATCH', `/api/leads/${id}`, { status: 'paid' }, { cookie, origin: BASE })).status, 400);
  assert.equal((await req('PATCH', `/api/leads/${id}`, { status: 'contacted' }, { cookie, origin: 'https://evil.example' })).status, 403);
});
await t('status change sets first_contact_at once and logs it', async () => {
  const r = await req('PATCH', `/api/leads/${id}`, { status: 'contacted', next_action_at: '2026-12-01' }, { cookie, origin: BASE });
  assert.equal(r.status, 200);
  const fc = r.j.data.lead.first_contact_at; assert.ok(fc);
  await req('PATCH', `/api/leads/${id}`, { status: 'quoted', value: 180 }, { cookie, origin: BASE });
  assert.equal(db.prepare('SELECT first_contact_at f FROM leads WHERE id=?').get(id).f, fc);
});
await t('lost needs a reason', async () => {
  assert.equal((await req('PATCH', `/api/leads/${id}`, { status: 'lost' }, { cookie, origin: BASE })).status, 400);
  assert.equal((await req('PATCH', `/api/leads/${id}`, { status: 'lost', lost_reason: 'price' }, { cookie, origin: BASE })).status, 200);
});
await t('board html is served after login', async () => {
  const r = await req('GET', '/admin', null, { cookie });
  assert.equal(r.status, 200); assert.match(r.text, /Lead board/);
});

// ---- cron ----
await t('late-lead alert fires once, in work hours only', async () => {
  db.prepare("UPDATE leads SET created_at = datetime('now','-2 hours') WHERE status='new'").run();
  sent.length = 0;
  // 15:05 UTC = 09:05 in America/Chicago (winter): inside work hours, not digest time
  const r1 = await runCron(env, new Date('2026-12-02T15:05:00Z'));
  assert.ok(r1.late_alerted >= 1, 'alerted');
  assert.equal(sent.length, 1);
  const r2 = await runCron(env, new Date('2026-12-02T15:20:00Z'));
  assert.equal(r2.late_alerted, 0, 'not twice');
  db.prepare("UPDATE leads SET sla_alerted = 0").run();
  const night = await runCron(env, new Date('2026-12-02T08:05:00Z')); // 02:05 local
  assert.equal(night.late_alerted, 0, 'no 2 a.m. ping');
});
await t('daily digest at DIGEST_HOUR local time', async () => {
  sent.length = 0;
  const r = await runCron(env, new Date('2026-12-02T14:05:00Z')); // 08:05 local
  assert.equal(r.digest, true);
  assert.ok(sent.some((s) => JSON.parse(s.body).text.includes('Follow-ups due')));
});

globalThis.fetch = realFetch;
console.log(`\n${passed} passed${process.exitCode ? ', some FAILED' : ''}`);
