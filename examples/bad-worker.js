// DO NOT DEPLOY. A deliberately broken booking Worker for practising the crm-hardening skill.
// Every mistake here is a real pattern found in a QA pass on a small booking site + CRM.
// Run: python skills/crm-hardening/scripts/audit_worker.py examples/bad-worker.js

const ADMIN_USER = 'admin';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const cors = { 'Access-Control-Allow-Origin': '*' };

    // Read endpoint "for the admin page". Nobody checks a session: the full guest list is public.
    if (url.pathname === '/api/bookings' && request.method === 'GET') {
      const { results } = await env.DB.prepare('SELECT * FROM bookings').all();
      return new Response(JSON.stringify(results), { headers: { 'content-type': 'application/json', ...cors } });
    }

    if (url.pathname === '/api/booking' && request.method === 'POST') {
      const body = await request.json();
      // Notify first, save second: if the bot is down the guest sees an error and submits again.
      await fetch(`https://api.telegram.org/bot${env.TG_TOKEN}/sendMessage`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ chat_id: env.TG_CHAT, parse_mode: 'HTML', text: `<b>New booking</b> ${body.name} ${body.phone}` }),
      });
      // Availability ignores 'paid' because this list was written before 'paid' existed.
      const busy = await env.DB.prepare(
        `SELECT COUNT(*) AS n FROM bookings WHERE cabin = '${body.cabin}' AND status IN ('new','confirmed')`
      ).first();
      if (busy.n > 0) return new Response('busy', { status: 409, headers: cors });
      await env.DB.prepare('INSERT INTO bookings (name, phone, cabin, status) VALUES (?, ?, ?, ?)')
        .bind(body.name, body.phone, body.cabin, 'new').run();
      return new Response('ok', { headers: cors });
    }

    if (url.pathname === '/api/login' && request.method === 'POST') {
      const body = await request.json();
      const password = env.ADMIN_PASSWORD || 'changeme123';
      if (body.password === password) {
        return new Response('ok', { headers: { 'set-cookie': `session=${ADMIN_USER}; Path=/` } });
      }
      return new Response('no', { status: 401 });
    }

    if (url.pathname === '/admin') {
      // The write token ships to every browser that opens this page.
      return new Response(`<script>const API = { 'write-token': 'wt_live_9f8e7d6c5b4a3210' };</script>`,
        { headers: { 'content-type': 'text/html' } });
    }

    if (url.pathname === '/api/booking/status' && request.method === 'PATCH') {
      try {
        const body = await request.json();
        const allowed = ['new', 'confirmed', 'paid', 'cancelled'];
        if (!allowed.includes(body.status)) return new Response('bad status', { status: 400 });
        await env.DB.prepare('UPDATE bookings SET status = ? WHERE id = ?').bind(body.status, body.id).run();
        return new Response('ok');
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message, stack: err.stack }), { status: 500 });
      }
    }
    return new Response('not found', { status: 404 });
  },
};
