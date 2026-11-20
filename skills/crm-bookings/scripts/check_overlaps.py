#!/usr/bin/env python3
"""Find double bookings in a mini-crm-site database (bookings add-on).

Reads a D1 export or a SQLite file, never writes. Reports every pair of bookings on the
same resource whose time ranges overlap while both hold the slot, plus bookings with
broken ranges and holds that should have expired.

Usage:
  python check_overlaps.py --dump crm.sql                    (npx wrangler d1 export crm --remote --output crm.sql)
  python check_overlaps.py --sqlite path/to/db.sqlite
  python check_overlaps.py --dump crm.sql --occupying held,confirmed,paid --now 2026-11-16T12:00

--occupying must match OCCUPYING_STATUSES in bookings.js. Run once with the list you
THINK is right and once with every non-cancelled status: if the second run finds
pairs the first does not, some code path treats a status as free that a guest thinks
is booked.

Exit 0 = clean, 1 = overlaps or broken rows found. Stdlib only.
"""
import argparse
import datetime as dt
import sqlite3
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--dump")
    g.add_argument("--sqlite")
    ap.add_argument("--occupying", default="held,confirmed,paid")
    ap.add_argument("--now", help="UTC time to judge expired holds, default: now")
    a = ap.parse_args()

    if a.sqlite:
        con = sqlite3.connect(f"file:{a.sqlite}?mode=ro", uri=True)
    else:
        con = sqlite3.connect(":memory:")
        with open(a.dump, encoding="utf-8") as f:
            con.executescript(f.read())
    occ = [s.strip() for s in a.occupying.split(",") if s.strip()]
    now = (dt.datetime.fromisoformat(a.now) if a.now else dt.datetime.utcnow()).strftime("%Y-%m-%d %H:%M:%S")
    q = ",".join("?" * len(occ))
    has_cap = {r[1] for r in con.execute("PRAGMA table_info(resources)")} >= {"capacity"}
    if not con.execute("SELECT name FROM sqlite_master WHERE name='bookings'").fetchone():
        print("no bookings table: is the bookings add-on installed?")
        return 1

    problems = 0
    pairs = con.execute(f"""
      SELECT a.id, b.id, r.name, a.start_at, a.end_at, a.status, b.start_at, b.end_at, b.status,
             {'r.capacity' if has_cap else '1'}
      FROM bookings a JOIN bookings b ON a.resource_id = b.resource_id AND a.id < b.id
      JOIN resources r ON r.id = a.resource_id
      WHERE a.status IN ({q}) AND b.status IN ({q})
        AND a.start_at < b.end_at AND b.start_at < a.end_at
        AND NOT (a.status='held' AND a.hold_until <= ?) AND NOT (b.status='held' AND b.hold_until <= ?)
      ORDER BY r.name, a.start_at""", occ + occ + [now, now]).fetchall()
    exclusive = [p for p in pairs if p[9] == 1]
    print(f"Overlapping pairs on exclusive resources (statuses {','.join(occ)}): {len(exclusive)}")
    for p in exclusive:
        print(f"  {p[2]}: #{p[0]} {p[3]}..{p[4]} ({p[5]})  vs  #{p[1]} {p[6]}..{p[7]} ({p[8]})")
    problems += len(exclusive)
    if any(p[9] > 1 for p in pairs):
        print("  (resources with capacity > 1 skipped: check them with a per-slot count)")

    bad = con.execute("SELECT id, start_at, end_at FROM bookings WHERE end_at <= start_at").fetchall()
    print(f"Bookings with end <= start: {len(bad)}")
    for b in bad:
        print(f"  #{b[0]} {b[1]}..{b[2]}")
    problems += len(bad)

    stale = con.execute("SELECT id, hold_until FROM bookings WHERE status='held' AND hold_until <= ?", (now,)).fetchall()
    print(f"Holds past hold_until still marked held: {len(stale)} (the release cron is not running?)")
    for s in stale[:20]:
        print(f"  #{s[0]} hold_until {s[1]}")

    print("CLEAN" if not problems else f"FOUND {problems} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
