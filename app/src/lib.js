// Pure helpers: validation, escaping, sessions, notifications. No database access here,
// so test/run.mjs can exercise them without Cloudflare.
import { SERVICES, STATUSES, FORM, BUSINESS } from './config.js';

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export function normalizePhone(raw) {
  const s = String(raw || '').trim();
  const plus = s.startsWith('+') ? '+' : '';
  const digits = s.replace(/\D/g, '');
  return plus + digits;
}

const clean = (v, max) => String(v == null ? '' : v).trim().slice(0, max);

// Server-side validation of the public form. The browser checks are a convenience;
// a bot posts straight to /api/lead and skips them.
// Returns { ok: true, lead } or { ok: false, error, field }.
export function validateLead(body, today = new Date().toISOString().slice(0, 10)) {
  if (!body || typeof body !== 'object') return { ok: false, error: 'Invalid request', field: null };
  const name = clean(body.name, FORM.maxName + 1);
  if (!name) return { ok: false, error: 'Please enter your name', field: 'name' };
  if (name.length > FORM.maxName) return { ok: false, error: 'Name is too long', field: 'name' };

  const phone = normalizePhone(body.phone);
  const digits = phone.replace('+', '').length;
  if (digits < FORM.minPhoneDigits || digits > FORM.maxPhoneDigits)
    return { ok: false, error: 'Please enter a phone number we can call', field: 'phone' };

  const email = clean(body.email, 200);
  if (email && !EMAIL.test(email)) return { ok: false, error: 'That email looks wrong', field: 'email' };
  if (FORM.requireEmail && !email) return { ok: false, error: 'Please enter your email', field: 'email' };

  const service = clean(body.service, 50);
  if (!Object.prototype.hasOwnProperty.call(SERVICES, service))
    return { ok: false, error: 'Please choose a service', field: 'service' };

  const preferred = clean(body.preferred_date, 10);
  if (preferred) {
    if (!ISO_DATE.test(preferred) || isNaN(new Date(preferred + 'T00:00:00Z')))
      return { ok: false, error: 'Date must be YYYY-MM-DD', field: 'preferred_date' };
    if (preferred < today) return { ok: false, error: 'That date is in the past', field: 'preferred_date' };
  }

  const message = clean(body.message, FORM.maxMessage + 1);
  if (message.length > FORM.maxMessage) return { ok: false, error: 'Message is too long', field: 'message' };

  return {
    ok: true,
    lead: {
      name, phone, email: email || null, service,
      preferred_date: preferred || null,
      area: clean(body.area, FORM.maxArea) || null,
      message: message || null,
      utm_source: clean(body.utm_source, 100).toLowerCase() || null,
      utm_medium: clean(body.utm_medium, 100).toLowerCase() || null,
      utm_campaign: clean(body.utm_campaign, 100).toLowerCase() || null,
    },
  };
}

// A filled honeypot means a bot. We answer "ok" so it does not retry with a smarter payload.
export function isHoneypotHit(body) {
  return Boolean(body && String(body.website || '').trim());
}

export function isValidStatus(s) {
  return Object.prototype.hasOwnProperty.call(STATUSES, s);
}

// Every user-typed field goes into an HTML-mode Telegram message through this.
// Without it a name like <a href=...> becomes a live link in the operator chat,
// and one stray "<" makes Telegram reject the whole message.
export function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

export function formatLeadMessage(lead, id, adminUrl) {
  const e = escapeHtml;
  const lines = [
    `<b>New lead #${id}</b> · ${e(BUSINESS.name)}`,
    `Name: ${e(lead.name)}`,
    `Phone: ${e(lead.phone)}`,
    `Service: ${e(SERVICES[lead.service] || lead.service)}`,
  ];
  if (lead.preferred_date) lines.push(`Date: ${e(lead.preferred_date)}`);
  if (lead.area) lines.push(`Area: ${e(lead.area)}`);
  if (lead.email) lines.push(`Email: ${e(lead.email)}`);
  if (lead.message) lines.push(`Message: ${e(lead.message)}`);
  if (lead.utm_source) lines.push(`Source: ${e(lead.utm_source)}${lead.utm_campaign ? ' / ' + e(lead.utm_campaign) : ''}`);
  if (adminUrl) lines.push(`<a href="${e(adminUrl)}">Open the board</a>`);
  return lines.join('\n');
}

// ---- sessions: HMAC-signed cookie, no password in the cookie ----

const enc = new TextEncoder();
const b64url = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function hmac(secret, data) {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return b64url(await crypto.subtle.sign('HMAC', key, enc.encode(data)));
}

export async function makeSession(secret, user, ttlSec = 7 * 86400, now = Date.now()) {
  const payload = `${user}.${Math.floor(now / 1000) + ttlSec}`;
  return `${payload}.${await hmac(secret, payload)}`;
}

export async function verifySession(secret, token, now = Date.now()) {
  if (!secret || !token) return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [user, exp, sig] = parts;
  if (Number(exp) * 1000 < now) return null;
  const good = await hmac(secret, `${user}.${exp}`);
  if (good.length !== sig.length) return null;
  let diff = 0;
  for (let i = 0; i < good.length; i++) diff |= good.charCodeAt(i) ^ sig.charCodeAt(i);
  return diff === 0 ? user : null;
}

export async function sameSecret(a, b) {
  // constant-time compare of two strings via their hashes
  const [x, y] = await Promise.all([a, b].map((s) => crypto.subtle.digest('SHA-256', enc.encode(String(s || '')))));
  const u = new Uint8Array(x), v = new Uint8Array(y);
  let diff = 0;
  for (let i = 0; i < u.length; i++) diff |= u[i] ^ v[i];
  return diff === 0 && Boolean(a) && Boolean(b);
}

export async function hashIp(ip, salt) {
  const d = await crypto.subtle.digest('SHA-256', enc.encode(`${salt || 'crm'}:${ip || 'unknown'}`));
  return b64url(d).slice(0, 22);
}

// Hour and date in the business timezone (Workers support Intl time zones).
export function localParts(date = new Date(), tz = BUSINESS.timezone) {
  const f = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23' });
  const p = Object.fromEntries(f.formatToParts(date).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, hour: Number(p.hour) };
}
