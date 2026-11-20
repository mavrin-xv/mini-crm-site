#!/usr/bin/env python3
"""Weekly lead report for mini-crm-site: where leads come from, how fast you call back,
what wins, what is rotting.

Input, one of:
  --dump FILE     SQL dump from `npx wrangler d1 export crm --remote --output crm.sql`
  --sqlite FILE   a SQLite file (for example the local dev DB under .wrangler/state/v3/d1/)

Options:
  --weeks N       how many recent weeks to show in the weekly table (default 8)
  --now ISO       pretend "now" is this UTC time (for reproducible reports), e.g. 2026-11-16T12:00
  --sla MIN       first-contact target in minutes (default 15, same as FIRST_CONTACT_SLA_MIN)
  --stale-days N  open lead with no touch for N days = stale (default 3)
  --json          print machine-readable JSON instead of text

Example:
  python report.py --dump ../../../examples/sample-data.sql --now 2026-11-16T12:00

Sections:
  1. Weekly volume and outcome
  2. Speed to lead: median minutes to first contact, share inside the SLA, and win rate
     for fast vs slow callbacks (your own data, not an industry claim)
  3. By source (utm_source / source): leads, booked, win rate, booked value
  4. Lost reasons
  5. Action list: new leads nobody called, overdue follow-ups, stale open leads
Stdlib only. Read-only: never writes to the database.
"""
import argparse
import datetime as dt
import json
import sqlite3
import statistics
import sys

OPEN = ("new", "contacted", "quoted", "booked")
WON = ("booked", "done")


def load(args):
    if args.sqlite:
        return sqlite3.connect(f"file:{args.sqlite}?mode=ro", uri=True)
    con = sqlite3.connect(":memory:")
    with open(args.dump, encoding="utf-8") as f:
        sql = f.read()
    # wrangler exports start with PRAGMA defer_foreign_keys; harmless here.
    con.executescript(sql)
    return con


def ts(s):
    return dt.datetime.strptime(s[:19], "%Y-%m-%d %H:%M:%S") if s else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--dump")
    g.add_argument("--sqlite")
    ap.add_argument("--weeks", type=int, default=8)
    ap.add_argument("--now")
    ap.add_argument("--sla", type=int, default=15)
    ap.add_argument("--stale-days", type=int, default=3)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    con = load(a)
    con.row_factory = sqlite3.Row
    rows = [dict(r) for r in con.execute(
        """SELECT l.*, c.name, c.phone FROM leads l JOIN contacts c ON c.id = l.contact_id""")]
    now = dt.datetime.fromisoformat(a.now) if a.now else dt.datetime.utcnow()
    real = [r for r in rows if r["status"] != "spam"]

    # 1. weekly
    weeks = {}
    for r in real:
        c = ts(r["created_at"])
        wk = (c - dt.timedelta(days=c.weekday())).strftime("%Y-%m-%d")
        w = weeks.setdefault(wk, {"week": wk, "leads": 0, "won": 0, "lost": 0, "open": 0, "value": 0})
        w["leads"] += 1
        if r["status"] in WON:
            w["won"] += 1
            w["value"] += r["value"] or 0
        elif r["status"] == "lost":
            w["lost"] += 1
        else:
            w["open"] += 1
    weekly = [weeks[k] for k in sorted(weeks)][-a.weeks:]

    # 2. speed to lead
    mins = []
    fast_won = fast_n = slow_won = slow_n = 0
    for r in real:
        if not r["first_contact_at"]:
            continue
        m = (ts(r["first_contact_at"]) - ts(r["created_at"])).total_seconds() / 60
        mins.append(m)
        if m <= a.sla:
            fast_n += 1
            fast_won += r["status"] in WON
        else:
            slow_n += 1
            slow_won += r["status"] in WON
    never = sum(1 for r in real if not r["first_contact_at"])
    speed = {
        "contacted": len(mins),
        "never_contacted": never,
        "median_min": round(statistics.median(mins), 1) if mins else None,
        "p90_min": round(sorted(mins)[int(len(mins) * 0.9) - 1], 1) if len(mins) >= 10 else None,
        "inside_sla_pct": round(100 * fast_n / len(mins)) if mins else None,
        "win_rate_fast_pct": round(100 * fast_won / fast_n) if fast_n else None,
        "win_rate_slow_pct": round(100 * slow_won / slow_n) if slow_n else None,
        "fast_n": fast_n, "slow_n": slow_n,
    }

    # 3. by source
    src = {}
    for r in real:
        k = r["utm_source"] or (r["source"] + " (no utm)" if r["source"] == "site" else r["source"]) or "unknown"
        if r["utm_campaign"]:
            k += " / " + r["utm_campaign"]
        s = src.setdefault(k, {"source": k, "leads": 0, "won": 0, "value": 0})
        s["leads"] += 1
        if r["status"] in WON:
            s["won"] += 1
            s["value"] += r["value"] or 0
    for s in src.values():
        s["win_rate_pct"] = round(100 * s["won"] / s["leads"]) if s["leads"] else 0
    by_source = sorted(src.values(), key=lambda s: (-s["value"], -s["leads"]))

    # 4. lost reasons
    reasons = {}
    for r in real:
        if r["status"] == "lost":
            k = (r["lost_reason"] or "(no reason given)").strip().lower()
            reasons[k] = reasons.get(k, 0) + 1
    lost = sorted(reasons.items(), key=lambda x: -x[1])

    # 5. actions
    sla_cut = now - dt.timedelta(minutes=a.sla)
    stale_cut = now - dt.timedelta(days=a.stale_days)
    uncalled = [r for r in real if r["status"] == "new" and ts(r["created_at"]) < sla_cut]
    overdue = [r for r in real if r["status"] in OPEN and r["next_action_at"] and r["next_action_at"][:10] <= now.strftime("%Y-%m-%d")]
    stale = [r for r in real if r["status"] in ("contacted", "quoted") and not r["next_action_at"]
             and ts(r["last_touch_at"] or r["created_at"]) < stale_cut]
    spam_share = round(100 * (len(rows) - len(real)) / len(rows)) if rows else 0

    out = {"now": now.isoformat(timespec="minutes"), "total_leads": len(rows), "spam_pct": spam_share,
           "weekly": weekly, "speed": speed, "by_source": by_source, "lost_reasons": lost,
           "actions": {
               "uncalled": [{"id": r["id"], "name": r["name"], "phone": r["phone"], "created_at": r["created_at"]} for r in uncalled],
               "overdue_followups": [{"id": r["id"], "name": r["name"], "status": r["status"], "due": r["next_action_at"]} for r in overdue],
               "stale_no_next_step": [{"id": r["id"], "name": r["name"], "status": r["status"], "last_touch": r["last_touch_at"]} for r in stale],
           }}
    if a.json:
        json.dump(out, sys.stdout, indent=2)
        print()
        return

    p = print
    p(f"Lead report  (now {out['now']} UTC, {len(rows)} leads, spam {spam_share}%)\n")
    p("1. Weekly")
    p(f"   {'week of':<11} {'leads':>5} {'won':>4} {'lost':>5} {'open':>5} {'won value':>10}")
    for w in weekly:
        p(f"   {w['week']:<11} {w['leads']:>5} {w['won']:>4} {w['lost']:>5} {w['open']:>5} {w['value']:>10}")
    p("\n2. Speed to lead")
    s = speed
    p(f"   median first contact: {s['median_min']} min" + (f", 90% within {s['p90_min']} min" if s['p90_min'] else ""))
    p(f"   inside {a.sla}-min target: {s['inside_sla_pct']}%   never contacted: {s['never_contacted']}")
    p(f"   win rate when called within {a.sla} min: {s['win_rate_fast_pct']}% (n={s['fast_n']})"
      f"  vs later: {s['win_rate_slow_pct']}% (n={s['slow_n']})")
    if s["fast_n"] < 20 or s["slow_n"] < 20:
        p("   (small sample: treat the gap as a hint, not proof)")
    p("\n3. By source (sorted by won value)")
    p(f"   {'source':<28} {'leads':>5} {'won':>4} {'win%':>5} {'value':>7}")
    for x in by_source:
        p(f"   {x['source'][:28]:<28} {x['leads']:>5} {x['won']:>4} {x['win_rate_pct']:>5} {x['value']:>7}")
    p("\n4. Lost reasons")
    for k, n in lost:
        p(f"   {n:>3}  {k}")
    p("\n5. Do today")
    act = out["actions"]
    p(f"   call now (new, past {a.sla} min): {len(act['uncalled'])}")
    for r in act["uncalled"][:10]:
        p(f"     #{r['id']} {r['name']} {r['phone']} since {r['created_at']}")
    p(f"   follow-ups due or overdue: {len(act['overdue_followups'])}")
    for r in act["overdue_followups"][:10]:
        p(f"     #{r['id']} {r['name']} ({r['status']}) due {r['due']}")
    p(f"   open with no next step for {a.stale_days}+ days: {len(act['stale_no_next_step'])}")
    for r in act["stale_no_next_step"][:10]:
        p(f"     #{r['id']} {r['name']} ({r['status']}) last touch {r['last_touch']}")


if __name__ == "__main__":
    main()
