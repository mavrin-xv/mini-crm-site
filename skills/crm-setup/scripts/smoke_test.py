#!/usr/bin/env python3
"""Live smoke test for a deployed (or `wrangler dev`) mini-crm-site.

Checks the things that break silently:
  1. GET  /api/health                 -> 200
  2. GET  /                           -> landing page with the lead form
  3. POST /api/lead (valid)           -> ok:true and an id
  4. POST /api/lead (same again)      -> same id, duplicate:true (dedup works)
  5. POST /api/lead (bad phone)       -> 400 with field "phone"
  6. POST /api/lead (bad service)     -> 400 with field "service"
  7. POST /api/lead (honeypot filled) -> ok:true, id null (bot silently dropped)
  8. GET  /api/leads without cookie   -> 401 (customer list is NOT public)
  9. GET  /api/stats without cookie   -> 401
 10. GET  /admin without cookie       -> 302 to /admin/login (or 503 if secrets missing)
With --password it also logs in, finds the test lead, moves it to "spam" and checks the event log.

Usage:
  python smoke_test.py http://127.0.0.1:8787
  python smoke_test.py https://your-site.example.workers.dev --password "$ADMIN_PASSWORD"
  ADMIN_PASSWORD=... python smoke_test.py https://your-site.example.workers.dev

The test lead uses the name "Smoke Test" and service "regular". It is marked spam at the end
when --password is given, so it never shows up as a real open lead.
Exit code 0 = all checks passed, 1 = at least one failed. Stdlib only.
"""
import argparse
import http.cookiejar
import json
import os
import random
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def make_opener(jar=None, follow=True):
    handlers = [urllib.request.HTTPCookieProcessor(jar or http.cookiejar.CookieJar())]
    if not follow:
        handlers.append(NoRedirect())
    return urllib.request.build_opener(*handlers)


def call(opener, method, url, body=None, origin=None, cookie=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("content-type", "application/json")
    req.add_header("user-agent", "mini-crm-smoke-test")
    if origin:
        req.add_header("origin", origin)
    if cookie:
        # Sent by hand: the session cookie is Secure, and Python's cookie jar
        # will not send Secure cookies to http://127.0.0.1 during local tests.
        req.add_header("cookie", cookie)
    try:
        with opener.open(req, timeout=20) as r:
            raw = r.read().decode("utf-8", "replace")
            return r.status, dict(r.headers), raw
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read().decode("utf-8", "replace")


def parse(raw):
    try:
        return json.loads(raw)
    except ValueError:
        return {}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("base", help="Base URL, e.g. http://127.0.0.1:8787")
    ap.add_argument("--password", default=os.environ.get("ADMIN_PASSWORD"), help="Admin password (or env ADMIN_PASSWORD)")
    args = ap.parse_args()
    base = args.base.rstrip("/")
    results = []

    def check(name, cond, detail=""):
        results.append(cond)
        print(f"[{'PASS' if cond else 'FAIL'}] {name}" + (f"  ({detail})" if detail and not cond else ""))
        return cond

    o = make_opener()
    s, _, raw = call(o, "GET", base + "/api/health")
    check("health endpoint answers", s == 200, f"status {s}")

    s, _, raw = call(o, "GET", base + "/")
    check("landing page has the lead form", s == 200 and 'id="lead"' in raw, f"status {s}")

    phone = "+1555" + str(random.randint(1000000, 9999999))
    lead = {"name": "Smoke Test", "phone": phone, "service": "regular", "message": "automated smoke test <b>x</b>"}
    s, _, raw = call(o, "POST", base + "/api/lead", lead)
    j = parse(raw)
    lead_id = (j.get("data") or {}).get("id")
    check("valid lead is saved", s == 200 and j.get("ok") is True and lead_id, f"status {s} body {raw[:200]}")

    s, _, raw = call(o, "POST", base + "/api/lead", lead)
    j = parse(raw)
    d = j.get("data") or {}
    check("resubmit is deduplicated", s == 200 and d.get("id") == lead_id and d.get("duplicate") is True, raw[:200])

    s, _, raw = call(o, "POST", base + "/api/lead", dict(lead, phone="12"))
    check("bad phone is rejected", s == 400 and parse(raw).get("field") == "phone", f"status {s} {raw[:200]}")

    s, _, raw = call(o, "POST", base + "/api/lead", dict(lead, service="free_money"))
    check("unknown service is rejected", s == 400 and parse(raw).get("field") == "service", f"status {s} {raw[:200]}")

    s, _, raw = call(o, "POST", base + "/api/lead", dict(lead, website="http://spam.example"))
    j = parse(raw)
    check("honeypot submit is dropped quietly", s == 200 and (j.get("data") or {}).get("id") is None, raw[:200])

    anon = make_opener(follow=False)
    s, _, raw = call(anon, "GET", base + "/api/leads")
    check("lead list needs login", s in (401, 503), f"status {s} (anything else means customer data is public)")
    s, _, raw = call(anon, "GET", base + "/api/stats")
    check("stats need login", s in (401, 503), f"status {s}")
    s, h, raw = call(anon, "GET", base + "/admin")
    loc = h.get("Location") or h.get("location") or ""
    check("admin redirects to login", (s in (301, 302, 303) and "/admin/login" in loc) or s == 503, f"status {s} location {loc}")

    if args.password:
        a = make_opener()
        s, _, raw = call(a, "POST", base + "/api/login", {"password": "definitely-wrong"})
        check("wrong password is refused", s == 401, f"status {s}")
        s, h, raw = call(a, "POST", base + "/api/login", {"password": args.password})
        set_cookie = h.get("Set-Cookie") or h.get("set-cookie") or ""
        check("session cookie is HttpOnly + Secure + SameSite", all(x in set_cookie for x in ("HttpOnly", "Secure", "SameSite")), set_cookie[:120])
        sess = set_cookie.split(";")[0]
        if check("login works", s == 200 and parse(raw).get("ok") and sess, f"status {s} {raw[:200]}"):
            s, _, raw = call(a, "GET", base + "/api/leads?q=Smoke", cookie=sess)
            leads = (parse(raw).get("data") or {}).get("leads") or []
            check("test lead is on the board", any(x.get("id") == lead_id for x in leads), f"status {s}")
            s, _, raw = call(a, "PATCH", base + f"/api/leads/{lead_id}", {"status": "nonsense"}, origin=base, cookie=sess)
            check("unknown status is rejected", s == 400, f"status {s}")
            s, _, raw = call(a, "PATCH", base + f"/api/leads/{lead_id}", {"status": "spam"}, origin="https://evil.example", cookie=sess)
            check("cross-origin change is refused", s == 403, f"status {s}")
            s, _, raw = call(a, "PATCH", base + f"/api/leads/{lead_id}", {"status": "spam"}, origin=base, cookie=sess)
            check("status change saves", s == 200 and (parse(raw).get("data") or {}).get("lead", {}).get("status") == "spam", raw[:200])
            s, _, raw = call(a, "GET", base + f"/api/leads/{lead_id}", cookie=sess)
            ev = (parse(raw).get("data") or {}).get("events") or []
            kinds = [e.get("kind") for e in ev]
            check("event log has created + status", "created" in kinds and "status" in kinds, str(kinds))
            notified = [k for k in kinds if k.startswith("notify")]
            print(f"[INFO] notification result: {notified or 'not logged yet (runs after the response)'}"
                  + (f"  note: {[e.get('note') for e in ev if e.get('kind','').startswith('notify')]}" if notified else ""))
    else:
        print("[SKIP] admin checks (pass --password or set ADMIN_PASSWORD)")

    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} checks passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
