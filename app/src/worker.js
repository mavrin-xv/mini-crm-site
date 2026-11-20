// mini-crm-site: one Worker serves the landing page (static assets in ../public),
// takes leads into D1, notifies the operator, and runs the admin board.
//
// Routes
//   POST /api/lead            public, validated, rate limited, deduplicated
//   GET  /admin               board (redirects to /admin/login without a session)
//   GET  /admin/login         login form
//   POST /api/login           password -> signed session cookie
//   POST /api/logout
//   GET  /api/leads           ?status=&q=        (session required)
//   GET  /api/leads/:id       lead + contact + events (session required)
//   PATCH /api/leads/:id      status / value / next_action_at / lost_reason (session required)
//   POST /api/leads/:id/notes (session required)
//   GET  /api/stats           counts per status, late leads, follow-ups due (session required)
//   GET  /api/health          public, no data
// Cron (wrangler.toml [triggers]): late-lead alerts during work hours + a daily digest.
//
// Secrets (wrangler secret put): ADMIN_PASSWORD, SESSION_SECRET, TG_BOT_TOKEN, TG_CHAT_ID,
// optional NOTIFY_WEBHOOK_URL, TURNSTILE_SECRET, PUBLIC_URL. There are no defaults in code:
// a missing ADMIN_PASSWORD or SESSION_SECRET closes the admin instead of opening it.

import {
  STATUSES, OPEN_STATUSES, FIRST_CONTACT_SLA_MIN, FORM, WORK_HOURS, DIGEST_HOUR, BUSINESS, SERVICES,
} from './config.js';
import {
  validateLead, isHoneypotHit, isValidStatus, escapeHtml, formatLeadMessage,
  makeSession, verifySession, sameSecret, hashIp, localParts,
} from './lib.js';
import { adminPage, loginPage } from './admin.js';

const COOKIE = 'crm_session';
const json = (data, status = 200, extra = {}) =>
  new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json; charset=utf-8', ...extra } });
const ok = (data) => json({ ok: true, data });
const fail = (status, error, field) => json({ ok: false, error, ...(field ? { field } : {}) }, status);
const html = (body, status = 200) =>
  new Response(body, { status, headers: { 'content-type': 'text/html; charset=utf-8', 'x-frame-options': 'DENY', 'cache-control': 'no-store' } });

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';
    try {
      if (path === '/api/health') return ok({ status: 'up' });
      if (path === '/api/lead' && request.method === 'POST') return await createLead(request, env, ctx);
      if (path === '/api/login' && request.method === 'POST') return await login(request, env);
      if (path === '/api/logout' && request.method === 'POST') return logout();
      if (path === '/admin/login') return html(loginPage(adminConfigured(env)));

      // Everything below needs a session. That includes every GET under /api:
      // a read endpoint without auth leaks the whole customer list.
      if (path === '/admin' || path.startsWith('/api/')) {
        if (!adminConfigured(env)) return path === '/admin' ? html(loginPage(false), 503) : fail(503, 'Admin is not configured');
        const user = await sessionUser(request, env);
        if (!user) return path === '/admin' ? Response.redirect(new URL('/admin/login', url).toString(), 302) : fail(401, 'Login required');
        if (request.method !== 'GET' && !sameOrigin(request, url)) return fail(403, 'Bad origin');
        if (path === '/admin') return html(adminPage());
        return await adminApi(request, env, path, url);
      }

      return env.ASSETS ? env.ASSETS.fetch(request) : new Response('Not found', { status: 404 });
    } catch (err) {
      console.error('request failed', path, err && err.stack);
      return fail(500, 'Something went wrong. Please call us instead.');
    }
  },

  async scheduled(controller, env, ctx) {
    ctx.waitUntil(runCron(env, new Date(controller.scheduledTime || Date.now())));
  },
};

// ---------------- public form ----------------

async function createLead(request, env, ctx) {
  let body;
  const type = request.headers.get('content-type') || '';
  try {
    body = type.includes('application/json')
      ? await request.json()
      : Object.fromEntries(await request.formData());
  } catch {
    return fail(400, 'Invalid request');
  }

  if (isHoneypotHit(body)) return ok({ id: null });

  if (env.TURNSTILE_SECRET) {
    const human = await verifyTurnstile(env.TURNSTILE_SECRET, body['cf-turnstile-response'], request.headers.get('cf-connecting-ip'));
    if (!human) return fail(400, 'Please confirm you are not a robot', 'captcha');
  }

  const v = validateLead(body);
  if (!v.ok) return fail(400, v.error, v.field);
  const lead = v.lead;

  const ipHash = await hashIp(request.headers.get('cf-connecting-ip'), env.SESSION_SECRET);
  const hits = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM form_hits WHERE ip_hash = ? AND at > datetime('now', '-10 minutes')"
  ).bind(ipHash).first();
  if (hits && hits.n >= FORM.rateLimitPerIpPer10Min) return fail(429, 'Too many requests. Please call us.');

  // Contact: phone is the key. Keep the newest name/email the person typed.
  const contact = await env.DB.prepare(
    `INSERT INTO contacts (name, phone, email) VALUES (?, ?, ?)
     ON CONFLICT(phone) DO UPDATE SET name = excluded.name, email = COALESCE(excluded.email, contacts.email)
     RETURNING id`
  ).bind(lead.name, lead.phone, lead.email).first();

  // Dedup: the same person asking for the same service inside the window is one lead.
  // People double-click, and they resubmit when the success message is slow.
  const dup = await env.DB.prepare(
    `SELECT id FROM leads WHERE contact_id = ? AND service = ?
       AND created_at > datetime('now', ?) ORDER BY id DESC LIMIT 1`
  ).bind(contact.id, lead.service, `-${FORM.dedupWindowMin} minutes`).first();

  await env.DB.prepare('INSERT INTO form_hits (ip_hash) VALUES (?)').bind(ipHash).run();

  if (dup) return ok({ id: dup.id, duplicate: true });

  // Save first, notify second. A dead Telegram must never lose a lead.
  const row = await env.DB.prepare(
    `INSERT INTO leads (contact_id, service, message, preferred_date, area, source, utm_source, utm_medium, utm_campaign)
     VALUES (?, ?, ?, ?, ?, 'site', ?, ?, ?) RETURNING id`
  ).bind(contact.id, lead.service, lead.message, lead.preferred_date, lead.area,
    lead.utm_source, lead.utm_medium, lead.utm_campaign).first();

  await env.DB.batch([
    env.DB.prepare("INSERT INTO lead_events (lead_id, kind, to_status) VALUES (?, 'created', 'new')").bind(row.id),
    env.DB.prepare("DELETE FROM form_hits WHERE at < datetime('now', '-1 day')"),
  ]);

  ctx.waitUntil(notifyNewLead(env, lead, row.id));
  return ok({ id: row.id });
}

async function verifyTurnstile(secret, token, ip) {
  if (!token) return false;
  const form = new FormData();
  form.append('secret', secret);
  form.append('response', token);
  if (ip) form.append('remoteip', ip);
  try {
    const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body: form });
    const data = await r.json();
    return data.success === true;
  } catch {
    return false;
  }
}

// ---------------- notifications ----------------

async function notifyNewLead(env, lead, id) {
  const adminUrl = env.PUBLIC_URL ? `${env.PUBLIC_URL.replace(/\/$/, '')}/admin#lead-${id}` : null;
  const result = await sendNotice(env, formatLeadMessage(lead, id, adminUrl));
  await env.DB.prepare('INSERT INTO lead_events (lead_id, kind, note) VALUES (?, ?, ?)')
    .bind(id, result.ok ? 'notify_ok' : 'notify_fail', result.detail.slice(0, 300)).run();
}

// Telegram (HTML mode) and/or a generic webhook ({"text": ...}, works for Slack and Discord-compatible hooks).
async function sendNotice(env, htmlText) {
  const results = [];
  if (env.TG_BOT_TOKEN && env.TG_CHAT_ID) {
    try {
      const r = await fetch(`https://api.telegram.org/bot${env.TG_BOT_TOKEN}/sendMessage`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ chat_id: env.TG_CHAT_ID, text: htmlText, parse_mode: 'HTML', disable_web_page_preview: true }),
      });
      const data = await r.json().catch(() => ({}));
      results.push(data.ok ? 'telegram ok' : `telegram ${r.status} ${data.description || ''}`.trim());
    } catch (e) {
      results.push(`telegram error ${e.message}`);
    }
  }
  if (env.NOTIFY_WEBHOOK_URL) {
    const plain = htmlText.replace(/<[^>]+>/g, '').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
    try {
      const r = await fetch(env.NOTIFY_WEBHOOK_URL, {
        method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ text: plain, content: plain }),
      });
      results.push(r.ok ? 'webhook ok' : `webhook ${r.status}`);
    } catch (e) {
      results.push(`webhook error ${e.message}`);
    }
  }
  if (!results.length) return { ok: false, detail: 'no channel configured' };
  return { ok: results.some((x) => x.endsWith(' ok')), detail: results.join('; ') };
}

// ---------------- auth ----------------

function adminConfigured(env) {
  return Boolean(env.ADMIN_PASSWORD && env.SESSION_SECRET && env.SESSION_SECRET.length >= 16);
}

function readCookie(request, name) {
  const raw = request.headers.get('cookie') || '';
  for (const part of raw.split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return v.join('=');
  }
  return null;
}

async function sessionUser(request, env) {
  return verifySession(env.SESSION_SECRET, readCookie(request, COOKIE));
}

function sameOrigin(request, url) {
  const origin = request.headers.get('origin');
  return !origin || origin === url.origin;
}

async function login(request, env) {
  if (!adminConfigured(env)) return fail(503, 'Admin is not configured');
  let body = {};
  try { body = await request.json(); } catch { /* empty body */ }
  if (!(await sameSecret(body.password, env.ADMIN_PASSWORD))) {
    await new Promise((r) => setTimeout(r, 400)); // slow down guessing
    return fail(401, 'Wrong password');
  }
  const token = await makeSession(env.SESSION_SECRET, 'operator');
  return json({ ok: true }, 200, {
    'set-cookie': `${COOKIE}=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${7 * 86400}`,
  });
}

function logout() {
  return json({ ok: true }, 200, { 'set-cookie': `${COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0` });
}

// ---------------- admin api ----------------

const LEAD_SELECT = `SELECT l.*, c.name, c.phone, c.email,
  (SELECT COUNT(*) FROM leads x WHERE x.contact_id = l.contact_id) AS contact_leads
  FROM leads l JOIN contacts c ON c.id = l.contact_id`;

async function adminApi(request, env, path, url) {
  if (path === '/api/leads' && request.method === 'GET') {
    const status = url.searchParams.get('status');
    const q = (url.searchParams.get('q') || '').trim().slice(0, 100);
    const where = [];
    const args = [];
    if (status) {
      if (!isValidStatus(status)) return fail(400, 'Unknown status');
      where.push('l.status = ?'); args.push(status);
    } else {
      where.push("(l.status NOT IN ('lost','spam') OR l.updated_at > datetime('now','-14 days'))");
    }
    if (q) {
      where.push('(c.name LIKE ? OR c.phone LIKE ? OR l.message LIKE ? OR l.area LIKE ?)');
      args.push(`%${q}%`, `%${q.replace(/\D/g, '') || q}%`, `%${q}%`, `%${q}%`);
    }
    const { results } = await env.DB.prepare(
      `${LEAD_SELECT} WHERE ${where.join(' AND ')} ORDER BY l.created_at DESC LIMIT 500`
    ).bind(...args).all();
    return ok({ leads: results, statuses: STATUSES, services: SERVICES, currency: BUSINESS.currency, sla_min: FIRST_CONTACT_SLA_MIN });
  }

  if (path === '/api/stats' && request.method === 'GET') return ok(await stats(env));

  const m = path.match(/^\/api\/leads\/(\d+)(\/notes)?$/);
  if (!m) return fail(404, 'Not found');
  const id = Number(m[1]);
  const current = await env.DB.prepare(`${LEAD_SELECT} WHERE l.id = ?`).bind(id).first();
  if (!current) return fail(404, 'Lead not found');

  if (!m[2] && request.method === 'GET') {
    const { results } = await env.DB.prepare('SELECT * FROM lead_events WHERE lead_id = ? ORDER BY id').bind(id).all();
    return ok({ lead: current, events: results });
  }

  let body;
  try { body = await request.json(); } catch { return fail(400, 'Invalid JSON'); }

  if (m[2] && request.method === 'POST') {
    const note = String(body.note || '').trim().slice(0, 2000);
    if (!note) return fail(400, 'Empty note');
    await env.DB.batch([
      env.DB.prepare("INSERT INTO lead_events (lead_id, kind, note) VALUES (?, 'note', ?)").bind(id, note),
      env.DB.prepare("UPDATE leads SET last_touch_at = datetime('now'), updated_at = datetime('now') WHERE id = ?").bind(id),
    ]);
    return ok({ id });
  }

  if (!m[2] && request.method === 'PATCH') {
    const sets = [];
    const args = [];
    const stmts = [];
    if ('status' in body) {
      if (!isValidStatus(body.status)) return fail(400, 'Unknown status');
      if (body.status === 'lost' && !String(body.lost_reason || current.lost_reason || '').trim())
        return fail(400, 'Say why the lead was lost', 'lost_reason');
      if (body.status !== current.status) {
        sets.push('status = ?'); args.push(body.status);
        if (current.status === 'new' && !current.first_contact_at) sets.push("first_contact_at = datetime('now')");
        stmts.push(env.DB.prepare("INSERT INTO lead_events (lead_id, kind, from_status, to_status) VALUES (?, 'status', ?, ?)")
          .bind(id, current.status, body.status));
      }
    }
    if ('value' in body) {
      const v = body.value === null || body.value === '' ? null : Number(body.value);
      if (v !== null && (!Number.isFinite(v) || v < 0 || v > 1e9)) return fail(400, 'Value must be a positive number', 'value');
      sets.push('value = ?'); args.push(v === null ? null : Math.round(v));
    }
    if ('next_action_at' in body) {
      const d = body.next_action_at ? String(body.next_action_at) : null;
      if (d && !/^\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?$/.test(d)) return fail(400, 'Use YYYY-MM-DD or YYYY-MM-DD HH:MM', 'next_action_at');
      sets.push('next_action_at = ?'); args.push(d);
    }
    if ('lost_reason' in body) {
      sets.push('lost_reason = ?'); args.push(String(body.lost_reason || '').trim().slice(0, 200) || null);
    }
    if (!sets.length) return fail(400, 'Nothing to change');
    sets.push("last_touch_at = datetime('now')", "updated_at = datetime('now')");
    stmts.unshift(env.DB.prepare(`UPDATE leads SET ${sets.join(', ')} WHERE id = ?`).bind(...args, id));
    await env.DB.batch(stmts);
    const fresh = await env.DB.prepare(`${LEAD_SELECT} WHERE l.id = ?`).bind(id).first();
    return ok({ lead: fresh });
  }

  return fail(405, 'Method not allowed');
}

async function stats(env) {
  const placeholders = OPEN_STATUSES.map(() => '?').join(',');
  const [byStatus, late, due] = await env.DB.batch([
    env.DB.prepare('SELECT status, COUNT(*) AS n FROM leads GROUP BY status'),
    env.DB.prepare("SELECT COUNT(*) AS n FROM leads WHERE status = 'new' AND created_at < datetime('now', ?)")
      .bind(`-${FIRST_CONTACT_SLA_MIN} minutes`),
    env.DB.prepare(`SELECT COUNT(*) AS n FROM leads WHERE status IN (${placeholders})
      AND next_action_at IS NOT NULL AND next_action_at <= datetime('now')`).bind(...OPEN_STATUSES),
  ]);
  return {
    by_status: Object.fromEntries(byStatus.results.map((r) => [r.status, r.n])),
    late_new: late.results[0].n,
    followups_due: due.results[0].n,
  };
}

// ---------------- cron ----------------

// Runs on every cron tick (see wrangler.toml.example: every 15 minutes).
// 1) Late-lead alert: 'new' leads older than the SLA, once per lead, only in work hours.
// 2) Daily digest at DIGEST_HOUR local time: open leads and follow-ups due today.
export async function runCron(env, now = new Date()) {
  const { hour, date } = localParts(now);
  const out = { late_alerted: 0, digest: false };

  if (hour >= WORK_HOURS.from && hour < WORK_HOURS.to) {
    const { results } = await env.DB.prepare(
      `${LEAD_SELECT} WHERE l.status = 'new' AND l.sla_alerted = 0
         AND l.created_at < datetime('now', ?) ORDER BY l.id LIMIT 20`
    ).bind(`-${FIRST_CONTACT_SLA_MIN} minutes`).all();
    if (results.length) {
      const lines = results.map((l) =>
        `#${l.id} ${escapeHtml(l.name)} ${escapeHtml(l.phone)} · ${escapeHtml(SERVICES[l.service] || l.service)} · waiting since ${escapeHtml(l.created_at)} UTC`);
      const r = await sendNotice(env, `<b>${results.length} lead(s) not called back in ${FIRST_CONTACT_SLA_MIN} min</b>\n${lines.join('\n')}`);
      if (r.ok) {
        await env.DB.prepare(`UPDATE leads SET sla_alerted = 1 WHERE id IN (${results.map(() => '?').join(',')})`)
          .bind(...results.map((l) => l.id)).run();
        out.late_alerted = results.length;
      }
    }
  }

  // The digest fires on the first tick inside DIGEST_HOUR. Cron runs every 15 min,
  // so "minute < 15" picks exactly one tick per day.
  if (hour === DIGEST_HOUR && now.getUTCMinutes() < 15) {
    const s = await stats(env);
    const placeholders = OPEN_STATUSES.map(() => '?').join(',');
    const { results } = await env.DB.prepare(
      `${LEAD_SELECT} WHERE l.status IN (${placeholders}) AND l.next_action_at IS NOT NULL
         AND substr(l.next_action_at, 1, 10) <= ? ORDER BY l.next_action_at LIMIT 30`
    ).bind(...OPEN_STATUSES, date).all();
    const open = OPEN_STATUSES.map((k) => `${STATUSES[k]}: ${s.by_status[k] || 0}`).join(' · ');
    const lines = results.map((l) => `#${l.id} ${escapeHtml(l.name)} ${escapeHtml(l.phone)} · ${escapeHtml(STATUSES[l.status])} · due ${escapeHtml(l.next_action_at)}`);
    const text = [`<b>${escapeHtml(BUSINESS.name)} · ${date}</b>`, open,
      `Not called back: ${s.late_new}`, `Follow-ups due: ${results.length}`, ...lines].join('\n');
    out.digest = (await sendNotice(env, text)).ok;
  }
  return out;
}
