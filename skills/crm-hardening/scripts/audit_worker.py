#!/usr/bin/env python3
"""Security and reliability audit for a small Cloudflare Worker that takes leads or bookings.

Two modes, use both:

  static   python audit_worker.py src/              scan .js/.ts files for known mistakes
  probe    python audit_worker.py --probe URL       hit a live site WITHOUT a login and look for leaks

Static checks (each finding has an id, severity and a fix; see references/qa-checklist.md):
  H01 high  credential fallback in code:   env.ADMIN_PASSWORD || 'admin123'
  H02 high  secret-looking literal next to an Authorization / token header or inside an HTML string
  H03 high  password or token compared with === / == (use a constant-time compare)
  H04 high  SQL built with ${...} inside prepare()/exec() (bind with ? instead)
  H05 high  parse_mode HTML used but no escape function in the file
  H06 med   Access-Control-Allow-Origin: * on an API that writes data
  H07 med   Set-Cookie without HttpOnly / Secure / SameSite
  H08 med   public POST handler with no rate limit or captcha in the file
  H09 med   notification sent before the database insert (a dead bot loses the lead)
  H10 med   error details (err.message / stack) returned to the client
  H11 med   two different status lists in one codebase (the "paid is not occupying" bug)
  H12 low   request.json() parsed without try/catch (a bad body becomes a 500)

Probe: GETs common data paths (/api/leads, /api/bookings, /api/contacts, /api/export, ...)
without cookies. A 200 with JSON data on any of them means customer data is public.
Also sends an empty POST to the lead endpoint to check it answers 400, not 500.

Exit code: 1 if any high finding or a probe leak, else 0. Stdlib only. Read-only.
"""
import argparse
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

RULES = [
    ("H01", "high", r"env\.[A-Z0-9_]*(PASS|SECRET|TOKEN|KEY)[A-Z0-9_]*\s*(\|\||\?\?)\s*['\"`]",
     "Credential has a hardcoded fallback. Remove it; fail closed (503) when the secret is missing."),
    ("H02", "high", r"(Bearer\s+[A-Za-z0-9_\-]{12,}['\"`]|['\"](x-)?(api|admin|write)[-_]?(key|token)['\"]\s*:\s*['\"][A-Za-z0-9_\-]{12,}['\"])",
     "Secret literal in code or served HTML. Move it to `wrangler secret put` and derive write access from the session."),
    ("H03", "high", r"(===?|!==?)\s*env\.[A-Z0-9_]*(PASS|TOKEN|SECRET)|env\.[A-Z0-9_]*(PASS|TOKEN|SECRET)[A-Z0-9_]*\s*(===?|!==?)",
     "Plain equality on a secret. Compare SHA-256 digests with a constant-time loop (see app/src/lib.js sameSecret)."),
    ("H04", "high", r"\.(prepare|exec)\(\s*`[^`]*\$\{(?!\s*(placeholders|sets\.join|where\.join|LEAD_SELECT|cols\.join))[^}]*\}",
     "SQL text built from a variable. Use ? placeholders and .bind(). Only join fixed, code-owned fragments."),
    ("H06", "med", r"Access-Control-Allow-Origin['\"]?\s*[:,]\s*['\"]\*['\"]",
     "CORS * lets any site post into your CRM from a visitor's browser. Same-origin needs no CORS header at all."),
    ("H10", "med", r"(JSON\.stringify|Response)\([^)]*\b(err|e|error)\.(message|stack)",
     "Internal error text goes to the client. Log it with console.error and return a fixed message."),
]


def scan_file(path, text):
    out = []
    lines = text.splitlines()

    def add(rid, sev, line_no, msg):
        out.append({"id": rid, "severity": sev, "file": str(path), "line": line_no, "fix": msg,
                    "code": lines[line_no - 1].strip()[:140] if 0 < line_no <= len(lines) else ""})

    for rid, sev, pat, msg in RULES:
        for m in re.finditer(pat, text):
            # placeholder lists like ${ids.map(() => '?').join(',')} are safe
            if rid == "H04" and re.search(r"=>\s*['\"]\?['\"]", text[m.start():m.end() + 40]):
                continue
            add(rid, sev, text.count("\n", 0, m.start()) + 1, msg)

    if re.search(r"parse_mode['\"]?\s*:\s*['\"]HTML", text) and not re.search(r"escape(Html|HTML)?\s*\(|\.replace\(/</g", text):
        ln = text.count("\n", 0, re.search(r"parse_mode", text).start()) + 1
        add("H05", "high", ln, "User input goes into an HTML-mode message unescaped. Escape & < > \" in every field.")

    for m in re.finditer(r"set-cookie['\"]?\s*[:,]\s*[`'\"]([^`'\"]*)", text, re.I):
        v = m.group(1)
        missing = [x for x in ("HttpOnly", "Secure", "SameSite") if x.lower() not in v.lower()]
        if missing and "Max-Age=0" not in v:
            add("H07", "med", text.count("\n", 0, m.start()) + 1, f"Cookie lacks {', '.join(missing)}.")

    has_public_post = re.search(r"method\s*===?\s*['\"]POST['\"]", text) and re.search(r"/api/(lead|booking|contact|order|request)", text)
    if has_public_post and not re.search(r"rate|429|turnstile|captcha|form_hits|honeypot", text, re.I):
        add("H08", "med", 1, "Public form endpoint with no rate limit, honeypot or Turnstile. Expect spam within weeks.")

    tg = re.search(r"api\.telegram\.org|sendMessage|NOTIFY_WEBHOOK|hooks\.slack", text)
    ins = re.search(r"INSERT\s+INTO", text, re.I)
    if tg and ins and tg.start() < ins.start():
        # only flag when the notify call sits inside the same function as the insert
        fn_start = text.rfind("function", 0, tg.start())
        fn_next = text.find("function", tg.start())
        if fn_next == -1 or ins.start() < fn_next:
            if fn_start != -1:
                add("H09", "med", text.count("\n", 0, tg.start()) + 1,
                    "Notification is sent before the row is saved. Save first, then notify in ctx.waitUntil and log the result.")

    status_lists = set()
    for m in re.finditer(r"\[\s*((?:['\"][a-z_]+['\"]\s*,\s*){2,}['\"][a-z_]+['\"])\s*,?\s*\]", text):
        items = tuple(sorted(re.findall(r"['\"]([a-z_]+)['\"]", m.group(1))))
        if any(x in items for x in ("new", "confirmed", "paid", "booked", "pending", "cancelled", "canceled")):
            status_lists.add(items)
    for m in re.finditer(r"IN\s*\(\s*((?:'[a-z_]+'\s*,\s*)+'[a-z_]+')\s*\)", text):
        items = tuple(sorted(re.findall(r"'([a-z_]+)'", m.group(1))))
        if any(x in items for x in ("confirmed", "paid", "booked", "pending")):
            status_lists.add(items)
    if len(status_lists) > 1:
        add("H11", "med", 1, "Several different status lists: " + " | ".join(",".join(s) for s in sorted(status_lists))
            + ". Keep ONE exported constant (e.g. OCCUPYING_STATUSES) and use it everywhere.")

    for m in re.finditer(r"await\s+request\.json\(\)", text):
        before = text[max(0, m.start() - 120):m.start()]
        if "try" not in before and ".catch" not in text[m.end():m.end() + 30]:
            add("H12", "low", text.count("\n", 0, m.start()) + 1, "Wrap request.json() in try/catch and answer 400.")
    return out


PROBE_PATHS = ["/api/leads", "/api/lead", "/api/bookings", "/api/booking", "/api/contacts", "/api/customers",
               "/api/clients", "/api/orders", "/api/export", "/api/stats", "/api/guests", "/api/requests",
               "/admin/api/leads", "/api/admin/leads"]


def probe(base):
    findings = []
    base = base.rstrip("/")
    for p in PROBE_PATHS:
        req = urllib.request.Request(base + p, headers={"user-agent": "mini-crm-audit"})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                body = r.read(20000).decode("utf-8", "replace")
                ctype = r.headers.get("content-type", "")
                status = r.status
        except urllib.error.HTTPError as e:
            status, body, ctype = e.code, "", ""
        except Exception as e:  # noqa: BLE001
            print(f"  {p:<22} error {e}")
            continue
        leak = status == 200 and "json" in ctype and re.search(r"\[\s*\{|\"(phone|name|email)\"", body)
        print(f"  {p:<22} {status} {'LEAK: returns data without login' if leak else ''}")
        if leak:
            findings.append({"id": "P01", "severity": "high", "file": base + p, "line": 0, "code": body[:120],
                             "fix": "Put this route behind the session check. Every GET under /api except health must need a login."})
    for p in ("/api/lead", "/api/booking"):
        req = urllib.request.Request(base + p, data=b"{not json", method="POST",
                                     headers={"content-type": "application/json", "user-agent": "mini-crm-audit"})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                status = r.status
        except urllib.error.HTTPError as e:
            status = e.code
        except Exception:  # noqa: BLE001
            continue
        if status >= 500:
            findings.append({"id": "P02", "severity": "med", "file": base + p, "line": 0, "code": f"POST bad JSON -> {status}",
                             "fix": "Bad input must give 400 with a message, not a 5xx."})
        print(f"  POST {p:<17} bad body -> {status}")
    return findings


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*", help="files or folders to scan")
    ap.add_argument("--probe", metavar="URL", help="live base URL to probe without a login")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    if not a.paths and not a.probe:
        ap.print_help()
        return 2

    findings = []
    for p in a.paths:
        root = pathlib.Path(p)
        files = [root] if root.is_file() else [f for f in root.rglob("*") if f.suffix in (".js", ".mjs", ".ts")
                                                and "node_modules" not in f.parts and ".wrangler" not in f.parts
                                                and "test" not in f.parts]
        for f in files:
            findings += scan_file(f, f.read_text(encoding="utf-8", errors="replace"))
    if a.probe:
        print(f"Probing {a.probe} without a login:")
        findings += probe(a.probe)

    if a.json:
        print(json.dumps(findings, indent=2))
    else:
        order = {"high": 0, "med": 1, "low": 2}
        for f in sorted(findings, key=lambda x: (order[x["severity"]], x["id"])):
            print(f"\n[{f['severity'].upper()}] {f['id']}  {f['file']}:{f['line']}\n  {f['code']}\n  fix: {f['fix']}")
        highs = sum(1 for f in findings if f["severity"] == "high")
        print(f"\n{len(findings)} findings ({highs} high)")
    return 1 if any(f["severity"] == "high" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
